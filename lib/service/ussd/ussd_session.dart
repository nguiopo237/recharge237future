import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

import 'sim_network.dart';
import 'ussd_screens.dart';

/// Résultat d'une session USSD, du point de vue de l'argent du client.
enum UssdOutcome {
  /// L'opérateur a confirmé l'opération.
  success,

  /// L'opérateur a refusé APRÈS validation (PIN) : rien n'a été exécuté
  /// selon son message (solde insuffisant, PIN incorrect...).
  failed,

  /// Arrêt AVANT la validation (PIN jamais envoyé) : aucun débit possible.
  notExecuted,

  /// PIN envoyé mais réponse absente ou non reconnue : l'opération a pu
  /// passer. À vérifier par l'admin, jamais relancée automatiquement.
  uncertain,
}

/// Interrompt la session avant validation avec une raison précise.
class UssdAbort implements Exception {
  final String reason;
  const UssdAbort(this.reason);
  @override
  String toString() => reason;
}

/// Une réponse possible à un écran USSD.
///
/// [answer] reçoit l'écran affiché et les étiquettes des règles déjà
/// utilisées. Il renvoie le texte à envoyer, ou `null` si la règle ne
/// s'applique pas à cet écran. Il peut lever [UssdAbort].
class UssdRule {
  final String label;
  final String? Function(String screen, Set<String> done) answer;

  /// Texte masqué dans les journaux (PIN).
  final bool secret;

  /// Envoyer cette réponse engage l'opération (en pratique : le PIN).
  /// L'écran suivant est la réponse finale de l'opérateur.
  final bool commits;
  final int maxUses;

  const UssdRule({
    required this.label,
    required this.answer,
    this.secret = false,
    this.commits = false,
    this.maxUses = 1,
  });
}

/// [MESURE 28/10/2026] Temps réellement passé sur UNE étape d'une session.
///
/// Sert à savoir où partent les secondes : l'attente de l'opérateur (qui
/// dépend de lui) et la réponse de l'app (qui dépend de nous).
class UssdStepTiming {
  /// 1 = premier écran de la session.
  final int step;

  /// Règle appliquée à cet écran (ou `lecture` si l'écran clôt la session).
  final String label;
  final bool secret;

  /// Envoi de la réponse précédente (ou numérotation) → écran reçu.
  final int screenWaitMs;

  /// Écran reçu → réponse partie (lecture, décision, saisie).
  final int replyMs;

  const UssdStepTiming({
    required this.step,
    required this.label,
    required this.screenWaitMs,
    required this.replyMs,
    this.secret = false,
  });

  Map<String, Object?> toMap() => <String, Object?>{
        'step': step,
        'label': label,
        'wait_ms': screenWaitMs,
        'reply_ms': replyMs,
      };

  String get line => 'étape $step ($label) : écran en $screenWaitMs ms, '
      'réponse en $replyMs ms';
}

class UssdRunResult {
  final UssdOutcome outcome;
  final String reason;
  final String finalScreen;
  final List<String> screens;
  final List<String> transcript;
  final bool retryable;

  /// [RESEAU 28/10/2026] Vrai quand la session a été refusée par la garde
  /// réseau : AUCUN code n'est parti. L'appelant doit alors GARDER la
  /// commande (rendre la réclamation, remettre le statut d'attente) pour
  /// qu'elle reparte au retour du réseau, au lieu de la marquer en échec.
  final bool networkBlocked;

  /// Mesure par étape (voir [UssdStepTiming]). Écrite dans la commande pour
  /// que la durée d'une session soit constatable après coup, sans adb.
  final List<UssdStepTiming> timings;

  /// Durée totale de la session, en millisecondes.
  final int totalMs;

  const UssdRunResult({
    required this.outcome,
    required this.reason,
    required this.finalScreen,
    required this.screens,
    required this.transcript,
    this.retryable = false,
    this.networkBlocked = false,
    this.timings = const <UssdStepTiming>[],
    this.totalMs = 0,
  });

  /// Temps passé à attendre l'opérateur (hors de notre contrôle).
  int get waitingMs =>
      timings.fold(0, (int s, UssdStepTiming t) => s + t.screenWaitMs);

  /// Temps passé par l'app à lire et répondre (ce que l'on peut réduire).
  int get respondingMs =>
      timings.fold(0, (int s, UssdStepTiming t) => s + t.replyMs);

  /// Résumé lisible pour Telegram et le journal Firestore.
  String get timingsLog {
    if (timings.isEmpty) return 'aucune étape mesurée';
    final String s =
        '${timings.length} étapes en ${(totalMs / 1000).toStringAsFixed(1)} s : '
        'attente opérateur ${(waitingMs / 1000).toStringAsFixed(1)} s, '
        'réponses app $respondingMs ms';
    final String detail =
        timings.map((UssdStepTiming t) => '  ${t.line}').join('\n');
    return '$s\n$detail';
  }

  /// Journal lisible (PIN masqué), pour Firestore et Telegram.
  String get log => transcript.join('\n');

  String get outcomeLabel {
    switch (outcome) {
      case UssdOutcome.success:
        return 'RÉUSSI';
      case UssdOutcome.failed:
        return 'REFUSÉ PAR L\'OPÉRATEUR';
      case UssdOutcome.notExecuted:
        return 'NON EXÉCUTÉ (aucun débit)';
      case UssdOutcome.uncertain:
        return '⚠️ À VÉRIFIER (PIN envoyé, réponse non confirmée)';
    }
  }

  /// Valeur du champ Firestore `ussd_outcome`.
  String get outcomeCode {
    switch (outcome) {
      case UssdOutcome.success:
        return 'succes';
      case UssdOutcome.failed:
        return 'refuse';
      case UssdOutcome.notExecuted:
        return 'non_execute';
      case UssdOutcome.uncertain:
        return 'a_verifier';
    }
  }

  String get summary => '$outcomeLabel\n$reason\n─────────────────────\n$log';
}

/// Pilote une session USSD étape par étape : compose le code, ATTEND chaque
/// écran de l'opérateur, vérifie ce qu'il demande, répond, et lit la
/// réponse finale.
///
/// Remplace l'envoi "à l'aveugle" du plugin `ussd_launcher`
/// (`multisessionUssd` enchaîne les réponses à délai fixe sans lire les
/// écrans : un montant pouvait partir dans le menu, le PIN dans le champ
/// du numéro...). Le plugin reste utilisé pour capter les écrans (service
/// d'accessibilité) ; la numérotation, les réponses et l'annulation passent
/// par le canal natif `r237/ussd` (MainActivity.kt).
///
/// Une seule session à la fois : les appels sont mis en file.
class UssdSessionRunner {
  UssdSessionRunner._();
  static final UssdSessionRunner instance = UssdSessionRunner._();

  static const MethodChannel _native = MethodChannel('r237/ussd');

  Future<void> _tail = Future<void>.value();
  final List<String> _inbox = <String>[];
  Completer<void>? _signal;

  /// Vrai tant qu'une session est en cours ou en file.
  ///
  /// [RESEAU 28/10/2026] Le cycle « mode avion » de récupération réseau refuse
  /// de se lancer pendant une session : couper la radio au milieu d'un menu
  /// USSD ferait échouer une opération que le client a déjà payée.
  bool get busy => _busy;
  bool _busy = false;

  /// Exécute une session. Voir [UssdRule] et [UssdOutcome].
  ///
  /// [isSuccess] juge la réponse finale après une règle `commits`.
  /// [isCompleteWithoutCommit] termine avec succès un parcours sans PIN
  /// (ex. lecture d'une liste d'offres) quand aucune règle ne s'applique.
  Future<UssdRunResult> run({
    required String code,
    required int slot,
    required List<UssdRule> rules,
    bool Function(String screen)? isSuccess,
    bool Function(String screen)? isCompleteWithoutCommit,
    Duration firstTimeout = const Duration(seconds: 40),
    Duration stepTimeout = const Duration(seconds: 25),
    Duration finalTimeout = const Duration(seconds: 50),
    int maxScreens = 12,
    String? expectedOperator,
  }) {
    final Future<void> previous = _tail;
    final Completer<void> mine = Completer<void>();
    _tail = mine.future;
    _busy = true;
    return previous.then((_) => _run(
          code: code,
          slot: slot,
          rules: rules,
          isSuccess: isSuccess,
          isCompleteWithoutCommit: isCompleteWithoutCommit,
          firstTimeout: firstTimeout,
          stepTimeout: stepTimeout,
          finalTimeout: finalTimeout,
          maxScreens: maxScreens,
          expectedOperator: expectedOperator,
        )).whenComplete(() {
      mine.complete();
      // La file est vide quand la session qui vient de finir était la dernière :
      // une session encore en attente garde le serveur occupé.
      if (identical(_tail, mine.future)) _busy = false;
    });
  }

  // [28/10/2026] Le relancement automatique (`runWithRetry`, 3 essais) a été
  // retiré : une commande ne doit être composée qu'UNE fois. Le résultat et
  // son motif partent dans le rapport ; c'est l'admin qui décide d'une
  // relance (bouton « Relancer » dans l'app serveur, ou `relance_demandee`
  // dans Firestore).

  /// [SANTE 29/10/2026] Vrai si le service d'accessibilité est actif et prêt
  /// (même contrôle qu'au début de chaque session). Publié dans
  /// `servers/{id}.accessibilityOk` par HealthWatch.
  Future<bool> accessibilityReady() async {
    try {
      return await UssdLauncher.isAccessibilityEnabled() &&
          (await _native.invokeMethod<bool>('serviceReady') ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Ferme une fenêtre USSD restée ouverte hors session (« Annuler »).
  ///
  /// [ORPHELINES 28/10/2026] Constaté en vrai : une session interrompue
  /// (application tuée, réseau perdu, téléphone redémarré) laisse le dialogue
  /// de l'opérateur à l'écran pendant des heures. Il masque l'app, bloque la
  /// commande suivante et l'admin croit le serveur figé.
  ///
  /// Rend `true` si une fenêtre a été trouvée et fermée.
  Future<bool> clearStaleDialog() async {
    try {
      final bool closed = await _native.invokeMethod<bool>('cancel') ?? false;
      if (closed) {
        debugPrint('[UssdSession] Fenêtre USSD orpheline fermée');
      }
      return closed;
    } catch (e) {
      debugPrint('[UssdSession] Fermeture impossible : $e');
      return false;
    }
  }

  void _onMessage(String message) {
    // [MESURE 28/10/2026] Trace de réception : permet de distinguer « l'écran
    // n'est jamais arrivé » de « l'écran est arrivé mais l'app ne répond pas ».
    debugPrint('[UssdSession] écran reçu à ${DateTime.now().toIso8601String()}'
        ' : ${oneLine(message).substring(0, oneLine(message).length.clamp(0, 60))}');
    _inbox.add(message);
    final Completer<void>? s = _signal;
    if (s != null && !s.isCompleted) s.complete();
  }

  final Random _rng = Random();

  /// Pause « humaine » : l'opérateur est manipulé comme le ferait une main sur
  /// l'écran, pas à cadence fixe.
  ///
  /// [28/10/2026] Resserrée : le geste d'une main entre la lecture d'un écran et
  /// la frappe est de quelques dizaines de millisecondes, pas d'un tiers de
  /// seconde. C'est du temps mort pur sur chaque étape d'une session.
  Future<void> _humanPause(int minMs, int maxMs) async {
    final int ms = minMs + _rng.nextInt(maxMs - minMs + 1);
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  /// Prochain écran de l'opérateur (écrans d'attente ignorés), différent
  /// de [differentFrom]. `null` si rien n'arrive.
  ///
  /// Le temps de réponse des opérateurs varie beaucoup (« Veuillez patienter… »
  /// peut durer 2 s ou 40 s). On attend donc comme un humain : dès qu'un écran
  /// d'attente arrive, l'échéance est repoussée de [timeout] — l'opérateur
  /// travaille encore — avec un plafond [maxTotal] pour ne jamais rester
  /// bloqué indéfiniment.
  /// Délai laissé à un écran ouvert mais vide de contenu avant de fermer la
  /// fenêtre. Un humain laisse au téléphone le temps de finir d'afficher, puis
  /// appuie sur « Annuler » sans attendre que l'opérateur expire.
  static const Duration _unreadableGrace = Duration(seconds: 8);

  /// Vrai quand la dernière session a été fermée par « Annuler » parce que
  /// l'écran de l'opérateur est resté vide (téléphone verrouillé).
  bool _closedUnreadable = false;

  /// Fenêtres d'information déjà fermées pendant la session en cours (garde
  /// contre une fenêtre qui se réafficherait en boucle).
  final Set<String> _closedInfoScreens = <String>{};

  Future<String?> _nextScreen(
    Duration timeout, {
    String? differentFrom,
    Duration maxTotal = const Duration(minutes: 4),
  }) async {
    final DateTime start = DateTime.now();
    final DateTime hardDeadline = start.add(maxTotal);
    DateTime deadline = start.add(timeout);
    DateTime? emptySince;
    String? emptyScreen;
    while (true) {
      while (_inbox.isNotEmpty) {
        final String m = _inbox.removeAt(0).trim();
        if (m.isEmpty) continue;
        // [MESURE 28/10/2026] Bandeau « INFOS SYSTEME DE OPERATEUR » : il
        // reste affiché et bloque le dialogue. On le ferme tout de suite,
        // comme le ferait un humain, puis on continue d'attendre l'écran
        // utile — au lieu de perdre la session.
        if (isBlockingInfoScreen(m)) {
          if (!_closedInfoScreens.contains(m) &&
              _closedInfoScreens.length < 3) {
            _closedInfoScreens.add(m);
            debugPrint('[UssdSession] Fenêtre d\'information fermée : '
                '${oneLine(m)}');
            await _closeDialog();
          }
          continue;
        }
        if (isTransientScreen(m)) {
          final DateTime renewed = DateTime.now().add(timeout);
          if (renewed.isAfter(deadline) && renewed.isBefore(hardDeadline)) {
            deadline = renewed;
          }
          continue;
        }
        if (differentFrom != null && m == differentFrom.trim()) continue;
        if (isUnusableScreen(m)) {
          // Le dialogue est bien là, mais son corps n'est pas peint : on
          // attend qu'il se complète, sinon on fermera la fenêtre.
          emptyScreen = m;
          emptySince ??= DateTime.now();
          debugPrint('[UssdSession] Écran sans contenu reçu : ${oneLine(m)}');
          continue;
        }
        return m;
      }

      final DateTime now = DateTime.now();
      DateTime cap = deadline.isBefore(hardDeadline) ? deadline : hardDeadline;
      if (emptySince != null) {
        final DateTime graceEnd = emptySince.add(_unreadableGrace);
        if (!now.isBefore(graceEnd)) {
          // Rien n'est venu : on ferme comme le ferait un humain, au lieu de
          // laisser la session expirer (et bloquer la commande suivante).
          debugPrint('[UssdSession] Écran vide depuis ${_unreadableGrace.inSeconds} s → Annuler');
          await _closeDialog();
          _closedUnreadable = true;
          return emptyScreen;
        }
        if (graceEnd.isBefore(cap)) cap = graceEnd;
      }
      final Duration left = cap.difference(now);
      if (left <= Duration.zero) return null;
      _signal = Completer<void>();
      try {
        await _signal!.future.timeout(left);
      } on TimeoutException {
        // boucle : vérifie une dernière fois la boîte puis rend null
      }
    }
  }

  Future<void> _closeDialog() async {
    try {
      final bool closed =
          await _native.invokeMethod<bool>('cancel') ?? false;
      if (closed) {
        debugPrint('[UssdSession] Fenêtre USSD fermée (Annuler)');
      }
    } catch (_) {}
  }

  Future<UssdRunResult> _run({
    required String code,
    required int slot,
    required List<UssdRule> rules,
    bool Function(String screen)? isSuccess,
    bool Function(String screen)? isCompleteWithoutCommit,
    required Duration firstTimeout,
    required Duration stepTimeout,
    required Duration finalTimeout,
    required int maxScreens,
    String? expectedOperator,
  }) async {
    final List<String> screens = <String>[];
    final List<String> log = <String>[];
    final Map<String, int> uses = <String, int>{};
    final List<UssdStepTiming> timings = <UssdStepTiming>[];
    // [ORPHELINES 28/10/2026] Avant de composer, on s'assure qu'aucun dialogue
    // n'est resté ouvert : sinon le nouveau code se superpose à l'ancien et la
    // session part en vrille. Aucun effet si l'écran est propre.
    await clearStaleDialog();
    final Stopwatch clock = Stopwatch()..start();
    // Instant (ms depuis le début) où la dernière réponse est partie.
    int lastSentAt = 0;
    bool committed = false;
    String lastScreen = '';
    _closedUnreadable = false;
    _closedInfoScreens.clear();

    UssdRunResult end(UssdOutcome o, String reason,
        {bool retryable = false, bool networkBlocked = false}) {
      final String shown = _closedUnreadable
          ? '$reason\nFenêtre USSD fermée avec « Annuler » : l\'écran de '
              'l\'opérateur est resté vide (téléphone verrouillé ou écran éteint).'
          : reason;
      log.add('= ${o.name} : ${oneLine(shown)}');
      final UssdRunResult result = UssdRunResult(
        outcome: o,
        reason: shown,
        finalScreen: lastScreen,
        screens: List<String>.unmodifiable(screens),
        transcript: List<String>.unmodifiable(log),
        // Un écran vide (téléphone verrouillé) ne se règle pas en relançant
        // aussitôt : la commande reste à traiter par l'admin.
        retryable: _closedUnreadable ? false : retryable,
        networkBlocked: networkBlocked,
        timings: List<UssdStepTiming>.unmodifiable(timings),
        totalMs: clock.elapsedMilliseconds,
      );
      debugPrint('[UssdSession] $code → ${o.name} : ${oneLine(shown)}');
      debugPrint('[Timing] $code → ${result.timingsLog}');
      return result;
    }

    // 1. Pré-requis : service d'accessibilité actif (il capte les écrans et
    //    tape les réponses).
    bool ready = false;
    try {
      ready = await UssdLauncher.isAccessibilityEnabled() &&
          (await _native.invokeMethod<bool>('serviceReady') ?? false);
    } catch (_) {}
    if (!ready) {
      return end(UssdOutcome.notExecuted,
          'Service d\'accessibilité de l\'app serveur désactivé : impossible de lire les écrans USSD.');
    }

    // 2. Le réseau de l'OPÉRATEUR doit être enregistré, sinon l'USSD n'aboutit
    //    jamais.
    //
    // [RESEAU 28/10/2026] Constaté en production : SIM `OUT_OF_SERVICE`, l'app
    // compose quand même, l'opérateur répond « Problème de connexion » après
    // plusieurs minutes (ou pas du tout) et la commande reste bloquée en « en
    // cours » alors que le client a payé. La garde [SimNetworkGuard] refuse en
    // une seconde, avec la vraie raison écrite dans la commande — et vérifie
    // au passage que l'emplacement contient bien la carte de l'opérateur visé.
    final SimNetworkCheck reseau = await SimNetworkGuard.check(
      slot,
      expected: expectedOperator,
    );
    if (!reseau.ok) {
      // `networkBlocked` : rien n'a été composé, la commande sera gardée.
      return end(UssdOutcome.notExecuted, reseau.reason, networkBlocked: true);
    }

    // 3. Ferme une éventuelle fenêtre USSD restée ouverte, puis compose.
    debugPrint('[UssdSession] préparation OK, fermeture d\'une éventuelle fenêtre');
    await _closeDialog();
    debugPrint('[UssdSession] fenêtre fermée, numérotation de $code (SIM ${slot + 1})');
    await _humanPause(100, 250);
    _inbox.clear();
    UssdLauncher.setUssdMessageListener(_onMessage);
    try {
      await _native.invokeMethod<void>('dial', <String, dynamic>{'code': code, 'slot': slot});
    } catch (e) {
      return end(UssdOutcome.notExecuted, 'Numérotation impossible : $e');
    }
    log.add('> $code (SIM ${slot + 1})');
    debugPrint('[UssdSession] code composé, attente du premier écran');

    String? screen = await _nextScreen(firstTimeout);
    debugPrint('[UssdSession] premier écran : ${screen == null ? 'aucun' : oneLine(screen)}');
    try {
      for (int i = 0; i < maxScreens; i++) {
        if (screen == null) {
          return committed
              ? end(UssdOutcome.uncertain,
                  'Aucune réponse de l\'opérateur après l\'envoi du PIN.')
              : end(UssdOutcome.notExecuted, 'Aucune réponse de l\'opérateur.',
                  retryable: true);
        }
        lastScreen = screen;
        screens.add(screen);
        log.add('< ${oneLine(screen)}');
        // [MESURE 28/10/2026] Temps que l'opérateur a mis à répondre.
        final int screenAt = clock.elapsedMilliseconds;
        final int waitMs = screenAt - lastSentAt;
        final UssdError? err = ussdErrorOf(screen);

        // Réponse finale après validation.
        if (committed) {
          if (isSuccess?.call(screen) ?? false) {
            return end(UssdOutcome.success, screen);
          }
          if (err != null) return end(UssdOutcome.failed, err.reason);
          return end(UssdOutcome.uncertain,
              'Réponse finale non reconnue : $screen');
        }

        if (err != null) {
          return end(UssdOutcome.notExecuted, err.reason,
              retryable: err.retryable);
        }

        // Choix de la réponse à cet écran.
        UssdRule? rule;
        String? reply;
        final Set<String> done = uses.keys.toSet();
        try {
          for (final UssdRule r in rules) {
            if ((uses[r.label] ?? 0) >= r.maxUses) continue;
            final String? a = r.answer(screen, done);
            if (a != null) {
              rule = r;
              reply = a;
              break;
            }
          }
        } on UssdAbort catch (a) {
          return end(UssdOutcome.notExecuted, a.reason);
        }

        if (rule == null || reply == null) {
          if (isCompleteWithoutCommit?.call(screen) ?? false) {
            return end(UssdOutcome.success, screen);
          }
          return end(UssdOutcome.notExecuted,
              'Écran inattendu, rien n\'a été validé : $screen');
        }

        uses[rule.label] = (uses[rule.label] ?? 0) + 1;
        log.add('> ${rule.secret ? '****' : reply}   (${rule.label})');
        // Réaction immédiate : dès que l'écran est lu, on répond, sans temps
        // mort ajouté — juste le geste de saisie d'une main sur le clavier.
        await _humanPause(25, 70);
        try {
          await _native.invokeMethod<void>('reply', <String, dynamic>{'text': reply});
        } catch (e) {
          return end(UssdOutcome.notExecuted, 'Réponse impossible à saisir : $e');
        }
        timings.add(UssdStepTiming(
          step: i + 1,
          label: rule.label,
          secret: rule.secret,
          screenWaitMs: waitMs,
          replyMs: clock.elapsedMilliseconds - screenAt,
        ));
        lastSentAt = clock.elapsedMilliseconds;
        if (rule.commits) committed = true;
        screen = await _nextScreen(rule.commits ? finalTimeout : stepTimeout,
            differentFrom: lastScreen);
      }
      return committed
          ? end(UssdOutcome.uncertain, 'Trop d\'écrans après l\'envoi du PIN.')
          : end(UssdOutcome.notExecuted, 'Trop d\'écrans, session abandonnée.');
    } finally {
      await _closeDialog();
    }
  }
}
