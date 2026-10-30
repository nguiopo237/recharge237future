import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../service/server/order_filters.dart'
    show canRelaunch, relaunchStatusFor;
import '../../service/server/status_labels.dart';

/// Carte d'une commande dans l'app serveur.
///
/// Objectif : qu'un opérateur qui surveille le téléphone comprenne une ligne
/// en une seconde — montant, numéro, opérateur, état, et la raison exacte en
/// cas d'échec. Un appui ouvre le détail (dont le journal USSD complet).
class TransactionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final VoidCallback? onLongPress;

  /// Relance manuelle (une seule tentative). `true` = relance acceptée.
  final Future<bool> Function()? onRelaunch;

  const TransactionCard({
    super.key,
    required this.data,
    required this.docId,
    this.onLongPress,
    this.onRelaunch,
  });

  // Motif numérique volontairement sans locale : `DateFormat` exigerait
  // `initializeDateFormatting` pour un nom de locale explicite.
  static final DateFormat _date = DateFormat('dd/MM/yyyy • HH:mm');
  static final NumberFormat _number = NumberFormat.decimalPattern('fr_FR');

  String get _amount {
    final Object? raw = data['amount'];
    final num? n = raw is num ? raw : num.tryParse('${raw ?? ''}');
    return n == null ? '—' : _number.format(n);
  }

  String get _target {
    final String raw = (data['numerocamtel'] ?? data['numerorecharge'] ?? '')
        .toString()
        .trim();
    return raw.isEmpty ? '—' : raw;
  }

  String get _time {
    final Object? raw = data['heure'];
    final DateTime? t = DateTime.tryParse('${raw ?? ''}');
    return t == null ? '—' : _date.format(t.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final ServerStatusInfo status = serverStatusInfo(data['status']);
    final String operator = operatorLabel(data);
    final Color opColor = operatorColor(operator);
    final String reason = (data['failure_reason'] ?? '').toString().trim();
    final bool showReason =
        reason.isNotEmpty && (status.isFailure || status.isPending);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetails(context),
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6EAF0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A06294D),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _OperatorPill(label: operator, color: opColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _time,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF7A8699),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  // Le statut garde sa largeur naturelle : c'est lui qui doit
                  // rester lisible, la date s'abrège si la place manque.
                  _StatusChip(status: status),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _amount,
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF06294D),
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Text(
                      'FCFA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7A8699),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const Icon(Icons.call_received_rounded,
                          size: 13, color: Color(0xFF7A8699)),
                      const SizedBox(width: 3),
                      Text(
                        _target,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF06294D),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (showReason) ...[
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: status.isFailure
                        ? const Color(0xFFFDECEC)
                        : const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: status.isFailure
                          ? const Color(0xFF9B1C1C)
                          : const Color(0xFF8A5A00),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final ServerStatusInfo status = serverStatusInfo(data['status']);
    final String operator = operatorLabel(data);
    final String log = (data['ussd_log'] ?? '').toString().trim();
    final String reason = (data['failure_reason'] ?? '').toString().trim();
    final String id = (data['idtransact'] ?? docId).toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          minChildSize: 0.35,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '$_amount FCFA',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF06294D),
                      ),
                    ),
                    const Spacer(),
                    _StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$operator • $_target',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7A8699),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                _DetailRow(label: 'Date', value: _time),
                _DetailRow(label: 'Identifiant', value: id),
                _DetailRow(
                  label: 'Payeur',
                  value: (data['numeroorange'] ?? '—').toString(),
                ),
                _DetailRow(
                  label: 'Type',
                  value: (data['type'] ?? '—').toString(),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Raison',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF7A8699),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    reason,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
                if (onRelaunch != null && canRelaunch(data)) ...[
                  const SizedBox(height: 18),
                  _RelaunchBlock(
                    executionStatus: relaunchStatusFor(data),
                    onRelaunch: onRelaunch!,
                  ),
                ],
                if (log.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'JOURNAL USSD',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF7A8699),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      log,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        height: 1.5,
                        color: Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _OperatorPill extends StatelessWidget {
  final String label;
  final Color color;
  const _OperatorPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ServerStatusInfo status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7A8699),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF06294D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Relance manuelle d'une commande déjà exécutée une fois.
///
/// Le serveur ne relance plus rien tout seul (une seule tentative, puis
/// rapport). Ce bloc est le seul endroit d'où une seconde tentative peut être
/// demandée depuis le téléphone — et il avertit, parce qu'une relance sur une
/// opération déjà passée crédite deux fois le client.
class _RelaunchBlock extends StatefulWidget {
  final String? executionStatus;
  final Future<bool> Function() onRelaunch;

  const _RelaunchBlock({
    required this.executionStatus,
    required this.onRelaunch,
  });

  @override
  State<_RelaunchBlock> createState() => _RelaunchBlockState();
}

class _RelaunchBlockState extends State<_RelaunchBlock> {
  bool _busy = false;

  Future<void> _confirmThenRelaunch() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Relancer cette commande ?'),
        content: const Text(
          'Une seule nouvelle tentative sera faite, puis le rapport sera '
          'envoyé comme d\'habitude.',
          style: TextStyle(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Relancer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final bool accepted = await widget.onRelaunch();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            accepted ? const Color(0xFF16A34A) : const Color(0xFFD90200),
        content: Text(
          accepted
              ? 'Relance demandée : le serveur fait une tentative, puis rend compte.'
              : 'Relance impossible : commande non payée, déjà livrée, ou déjà en file.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String status = widget.executionStatus ?? '1';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.restart_alt_rounded,
                  size: 16, color: Color(0xFF06294D)),
              SizedBox(width: 6),
              Text(
                'Relance manuelle',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF06294D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Le serveur a exécuté cette commande une seule fois. Vérifiez chez '
            'l\'opérateur que le crédit n\'est pas déjà parti avant de relancer.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: Color(0xFF7A8699),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'À distance, dans Firestore : relance_demandee = true et status = '
            '« $status ».',
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Color(0xFF7A8699),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _confirmThenRelaunch,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: Text(_busy ? 'Relance…' : 'Relancer cette commande'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF06294D),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
