import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../main.dart' show serverAuthUid;
import '../../service/sendmail/send_mail.dart';
import '../../service/server/server_manager.dart';
import '../../service/server/sim_probe.dart';
import '../../service/server/slot_config.dart';
import '../../service/ussd/sim_network.dart';

/// [CONFIG SIM 29/10/2026] Configuration des SIM directement sur le
/// téléphone serveur, sans passer par la console Firebase.
///
/// L'admin qui a le téléphone en main voit chaque carte détectée et ne fait
/// que des CHOIX : rôle de la carte (seuls ceux de son opérateur sont
/// proposés), PIN, activation, seuil d'alerte. Tout est contrôlé avant
/// l'enregistrement (cf. `validateSlots`), puis écrit dans
/// `servers/{deviceId}.slots` — le même format que l'écran admin de l'app
/// Recharge237. Le téléphone applique la configuration dans la seconde.
class SimConfigScreen extends StatefulWidget {
  const SimConfigScreen({super.key});

  @override
  State<SimConfigScreen> createState() => _SimConfigScreenState();
}

class _SlotForm {
  final int slot;
  DetectedSim? sim;
  String code;
  bool active;
  String savedPin;
  final TextEditingController pin = TextEditingController();
  final TextEditingController seuil = TextEditingController();
  bool pinVisible = false;
  String? reseau;
  bool reseauOk = false;
  bool test = false;

  _SlotForm(this.slot,
      {this.sim,
      this.code = kSlotFree,
      this.active = false,
      this.savedPin = ''});

  String get detected => sim?.operator ?? '';

  /// PIN retenu : le nouveau s'il est saisi, sinon celui déjà enregistré.
  String get effectivePin =>
      pin.text.trim().isNotEmpty ? pin.text.trim() : savedPin;

  SlotSpec toSpec() => SlotSpec(
        slot: slot,
        code: code,
        pin: effectivePin,
        active: active && code.isNotEmpty,
        minBalance: int.tryParse(seuil.text.trim()) ?? 0,
      );

  void dispose() {
    pin.dispose();
    seuil.dispose();
  }
}

class _SimConfigScreenState extends State<SimConfigScreen> {
  static const Color _bleu = Color(0xFF06294D);

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;
  String _modele = '';
  final TextEditingController _nom = TextEditingController();
  List<_SlotForm> _slots = <_SlotForm>[];

  String get _deviceId => ServerManager.instance.deviceId;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _nom.dispose();
    for (final _SlotForm f in _slots) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final DetectedHardware? hw = await SimProbe.detect();
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection('servers')
          .doc(_deviceId)
          .get()
          .timeout(const Duration(seconds: 15));
      final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
      final List<SlotSpec> declares = slotSpecsFromDocument(d);

      final Set<int> emplacements = <int>{0, 1};
      for (final DetectedSim s in hw?.sims ?? const <DetectedSim>[]) {
        emplacements.add(s.slot);
      }
      for (final SlotSpec s in declares) {
        emplacements.add(s.slot);
      }

      final List<_SlotForm> forms = <_SlotForm>[];
      for (final int slot in emplacements.toList()..sort()) {
        DetectedSim? sim;
        for (final DetectedSim s in hw?.sims ?? const <DetectedSim>[]) {
          if (s.slot == slot) sim = s;
        }
        SlotSpec? decl;
        for (final SlotSpec s in declares) {
          if (s.slot == slot) decl = s;
        }
        final _SlotForm f = _SlotForm(
          slot,
          sim: sim,
          code: decl?.code ?? kSlotFree,
          active: decl?.active ?? false,
          savedPin: decl?.pin ?? '',
        );
        // Rôle par défaut pour une carte détectée mais pas encore déclarée.
        if (f.code.isEmpty && sim != null) {
          final List<String> choix = codesForDetectedOperator(sim.operator);
          if (choix.length == 1) f.code = choix.first;
        }
        if ((decl?.minBalance ?? 0) > 0) f.seuil.text = '${decl!.minBalance}';
        forms.add(f);
      }

      for (final _SlotForm f in _slots) {
        f.dispose();
      }
      if (!mounted) return;
      setState(() {
        _modele = [hw?.manufacturer ?? '', hw?.model ?? '']
            .where((String e) => e.isNotEmpty)
            .join(' ');
        _nom.text = (d['name'] ?? '').toString();
        _slots = forms;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = 'Lecture impossible : $e';
      });
    }
  }

  Map<int, String> get _detection => <int, String>{
        for (final _SlotForm f in _slots)
          if (f.detected.isNotEmpty) f.slot: f.detected,
      };

  List<String> get _problemes => validateSlots(
        _slots.map((_SlotForm f) => f.toSpec()).toList(),
        detected: _detection,
      );

  Future<void> _tester(_SlotForm f) async {
    final String op = operatorOfCode(f.code);
    setState(() {
      f.test = true;
      f.reseau = null;
    });
    final SimNetworkCheck r = await SimNetworkGuard.check(
      f.slot,
      expected: op.isEmpty ? null : op,
      maxWait: const Duration(seconds: 10),
    );
    if (!mounted) return;
    setState(() {
      f.test = false;
      f.reseauOk = r.ok;
      f.reseau = r.ok ? 'Réseau OK — ${r.state.summary}' : r.reason;
    });
  }

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();
    final List<String> problemes = _problemes;
    if (problemes.isNotEmpty) {
      _snack(problemes.first, Colors.red);
      return;
    }
    final List<SlotSpec> specs =
        _slots.map((_SlotForm f) => f.toSpec()).toList();
    final List<String> handles = handlesForSlots(specs);
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Enregistrer la configuration ?'),
            content: Text(
              'Ce téléphone livrera :\n'
              '${specs.where((SlotSpec s) => s.isPresent).map((SlotSpec s) => '• SIM ${s.slot + 1} → ${slotCodeLabel(s.code)}').join('\n')}\n\n'
              'Les commandes de ces opérateurs lui seront confiées dès '
              'l\'enregistrement.',
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Enregistrer')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _enregistrement = true);
    try {
      await FirebaseFirestore.instance
          .collection('servers')
          .doc(_deviceId)
          .set(<String, dynamic>{
        if (_nom.text.trim().isNotEmpty) 'name': _nom.text.trim(),
        'slots': specs.map((SlotSpec s) => s.toMap()).toList(),
        // Écrit pour l'écran admin et les anciennes versions ; le serveur
        // le déduit lui-même de `slots`.
        'handles': handles,
        'configUpdatedAt': FieldValue.serverTimestamp(),
        'configUpdatedBy': 'serveur:$serverAuthUid',
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));
      // Jamais de PIN dans le message.
      SendEmail.sendMessagewithtelegram(
        message: 'Recharge237 — SIM CONFIGURÉES SUR LE TÉLÉPHONE\n'
            'Téléphone : ${_nom.text.trim().isEmpty ? _deviceId : '${_nom.text.trim()} ($_deviceId)'}\n'
            '${specs.map((SlotSpec s) => 'SIM ${s.slot + 1} : ${s.isPresent ? slotCodeLabel(s.code) : 'non utilisée'}').join('\n')}',
      ).catchError((Object _) {});
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _snack('Enregistrement impossible : $e', Colors.red);
    }
  }

  void _snack(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: _bleu,
        title: const Text('Configurer les SIM',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: <Widget>[
          IconButton(
            tooltip: 'Redétecter les cartes',
            onPressed: _chargement ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _message(_erreur!)
              : _formulaire(),
      bottomNavigationBar: _chargement || _erreur != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF006CD9),
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: _enregistrement ? null : _enregistrer,
                  icon: _enregistrement
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded),
                  label: const Text('Enregistrer',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded, size: 44, color: Colors.red),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _charger, child: const Text('Réessayer')),
            ],
          ),
        ),
      );

  Widget _formulaire() {
    final List<String> problemes = _problemes;
    final List<SlotSpec> specs =
        _slots.map((_SlotForm f) => f.toSpec()).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        _carte(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_modele.isEmpty ? 'Ce téléphone' : _modele,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: _bleu, fontSize: 15)),
              const SizedBox(height: 2),
              Text('ID $_deviceId',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF7A8699))),
              const SizedBox(height: 12),
              TextField(
                controller: _nom,
                decoration: const InputDecoration(
                  labelText: 'Nom du téléphone (facultatif)',
                  hintText: 'ex. CAMTEL #1',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        for (final _SlotForm f in _slots) _carteSim(f),
        _carte(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Ce téléphone livrera',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _bleu)),
              const SizedBox(height: 8),
              if (!specs.any((SlotSpec s) => s.isPresent))
                const Text('Aucune commande pour l\'instant.')
              else
                for (final SlotSpec s
                    in specs.where((SlotSpec s) => s.isPresent))
                  Text('• ${slotCodeLabel(s.code)} (SIM ${s.slot + 1})'),
              if (problemes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                for (final String p in problemes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.error_outline_rounded,
                            size: 16, color: Colors.red),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(p,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 13))),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _carteSim(_SlotForm f) {
    final DetectedSim? sim = f.sim;
    // Seuls les rôles de l'opérateur détecté, plus le rôle déjà enregistré
    // s'il ne correspond plus à la carte (la validation le signale).
    final List<String> options = <String>{
      ...codesForDetectedOperator(f.detected),
      if (f.code.isNotEmpty) f.code,
    }.toList();
    final String detail = sim == null
        ? 'Aucune carte détectée'
        : '${sim.carrier.isEmpty ? 'Opérateur inconnu' : sim.carrier}'
            '${sim.number.isNotEmpty ? ' · ${sim.number}' : ''}'
            '${sim.mccMnc.isNotEmpty ? ' · ${sim.mccMnc}' : ''}';
    return _carte(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.sim_card_rounded,
                  color: sim == null ? Colors.grey : const Color(0xFF006CD9)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('SIM ${f.slot + 1}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, color: _bleu)),
                    Text(detail,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF7A8699))),
                  ],
                ),
              ),
              Switch(
                value: f.active,
                onChanged: sim == null && !f.active
                    ? null
                    : (bool v) => setState(() => f.active = v),
              ),
            ],
          ),
          if (f.active) ...<Widget>[
            const SizedBox(height: 10),
            const Text('Rôle de cette carte',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String code in options)
                  ChoiceChip(
                    label: Text(slotCodeLabel(code)),
                    selected: f.code == code,
                    onSelected: (_) => setState(() {
                      f.code = code;
                      f.reseau = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: f.pin,
              obscureText: !f.pinVisible,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: f.savedPin.isEmpty
                    ? 'PIN de la carte'
                    : 'Nouveau PIN (vide = garder l\'actuel)',
                helperText:
                    f.savedPin.isEmpty ? null : 'Un PIN est déjà enregistré',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(f.pinVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded),
                  onPressed: () => setState(() => f.pinVisible = !f.pinVisible),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: f.seuil,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Alerte solde bas (FCFA, facultatif)',
                hintText: 'vide = seuil général',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: f.test || f.code.isEmpty ? null : () => _tester(f),
                  icon: f.test
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: const Text('Vérifier le réseau'),
                ),
              ],
            ),
            if (f.reseau != null)
              Text(f.reseau!,
                  style: TextStyle(
                      fontSize: 12,
                      color: f.reseauOk ? Colors.green[700] : Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _carte(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3E8F0)),
        ),
        child: child,
      );
}
