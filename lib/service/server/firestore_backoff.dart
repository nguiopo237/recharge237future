import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// [QUOTA 29/10/2026] Backoff exponentiel partagé pour tous les accès
/// Firestore du serveur.
///
/// Constat du 28/10 : dès que le quota Firestore est atteint
/// (`RESOURCE_EXHAUSTED`), le téléphone et les scripts du PC continuaient à
/// interroger la base chaque minute — chaque essai raté retardait d'autant le
/// retour à la normale et noyait les journaux.
///
/// Règle : à la première erreur de saturation (ou de base injoignable), on
/// attend [base] ; à chaque nouvel échec l'attente DOUBLE, plafonnée à
/// [plafond] (5 min). Le premier succès remet tout à zéro. Pendant la pause,
/// les tâches périodiques (battement, relevé réseau, rapports) sautent leur
/// tour au lieu d'insister.
///
/// Un seul état pour tout le téléphone : quand le quota est atteint, il l'est
/// pour toutes les requêtes à la fois.
class FirestoreBackoff {
  FirestoreBackoff({
    this.base = const Duration(seconds: 5),
    this.plafond = const Duration(minutes: 5),
    DateTime Function()? horloge,
    Random? aleatoire,
  })  : _horloge = horloge ?? DateTime.now,
        _aleatoire = aleatoire ?? Random();

  /// Instance commune à tout le serveur.
  static final FirestoreBackoff instance = FirestoreBackoff();

  final Duration base;
  final Duration plafond;
  final DateTime Function() _horloge;
  final Random _aleatoire;

  Duration _attente = Duration.zero;
  DateTime? _pauseJusqua;
  int _echecsConsecutifs = 0;
  bool _saturation = false;

  /// Vrai tant qu'on doit laisser la base tranquille.
  bool get enPause {
    final DateTime? fin = _pauseJusqua;
    return fin != null && _horloge().isBefore(fin);
  }

  /// Temps restant avant le prochain essai autorisé.
  Duration get resteAttente {
    final DateTime? fin = _pauseJusqua;
    if (fin == null) return Duration.zero;
    final Duration reste = fin.difference(_horloge());
    return reste.isNegative ? Duration.zero : reste;
  }

  /// Dernière attente appliquée (sans la petite part aléatoire).
  Duration get attenteCourante => _attente;

  int get echecsConsecutifs => _echecsConsecutifs;

  /// Vrai si la dernière erreur était un dépassement de quota.
  bool get saturation => _saturation;

  /// Erreur de quota Firestore (`RESOURCE_EXHAUSTED`).
  static bool estSaturation(Object erreur) {
    if (erreur is FirebaseException && erreur.code == 'resource-exhausted') {
      return true;
    }
    final String texte = erreur.toString();
    return texte.contains('RESOURCE_EXHAUSTED') ||
        texte.contains('resource-exhausted') ||
        texte.contains('Quota exceeded');
  }

  /// Erreur qui vaut la peine d'être retentée plus tard (quota, base
  /// injoignable, délai dépassé). Les erreurs de droits ou de données, elles,
  /// ne se corrigent pas en attendant.
  static bool estTransitoire(Object erreur) {
    if (estSaturation(erreur)) return true;
    if (erreur is TimeoutException) return true;
    if (erreur is FirebaseException) {
      return erreur.code == 'unavailable' ||
          erreur.code == 'deadline-exceeded' ||
          erreur.code == 'aborted' ||
          erreur.code == 'internal';
    }
    return false;
  }

  /// Enregistre un échec et renvoie l'attente à respecter avant le prochain
  /// essai : [base], puis le double à chaque échec, jamais plus que [plafond].
  /// Une part aléatoire (0 à 20 %) évite que plusieurs téléphones repartent
  /// tous à la même seconde.
  Duration echec([Object? erreur]) {
    _echecsConsecutifs++;
    _saturation = erreur != null && estSaturation(erreur);
    final Duration suivante =
        _attente == Duration.zero ? base : _attente * 2;
    _attente = suivante > plafond ? plafond : suivante;
    final int alea =
        (_attente.inMilliseconds * 0.2 * _aleatoire.nextDouble()).round();
    final Duration avecAlea = _attente + Duration(milliseconds: alea);
    _pauseJusqua = _horloge().add(avecAlea);
    debugPrint('[Backoff] échec n°$_echecsConsecutifs'
        '${_saturation ? ' (QUOTA)' : ''} — pause ${avecAlea.inSeconds} s');
    return avecAlea;
  }

  /// Le premier succès efface la pause.
  void succes() {
    if (_echecsConsecutifs > 0) {
      debugPrint('[Backoff] base de nouveau joignable après '
          '$_echecsConsecutifs échec(s)');
    }
    _attente = Duration.zero;
    _pauseJusqua = null;
    _echecsConsecutifs = 0;
    _saturation = false;
  }

  /// Exécute [operation] si la base n'est pas en pause.
  ///
  /// Renvoie `null` si l'appel est sauté (pause en cours) ou s'il échoue pour
  /// une raison transitoire — l'échec est alors compté. Les autres erreurs
  /// sont relancées telles quelles.
  Future<T?> executer<T>(Future<T> Function() operation) async {
    if (enPause) return null;
    try {
      final T resultat = await operation();
      succes();
      return resultat;
    } catch (e) {
      if (!estTransitoire(e)) rethrow;
      echec(e);
      return null;
    }
  }
}
