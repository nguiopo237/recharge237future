import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:telephony/telephony.dart';

import '../../main.dart';

class RealtimeSmsReaderScreen extends StatefulWidget {
  @override
  _RealtimeSmsReaderScreenState createState() =>
      _RealtimeSmsReaderScreenState();
}

class _RealtimeSmsReaderScreenState extends State<RealtimeSmsReaderScreen> {
  final Telephony telephony = Telephony.instance;
  List<SmsMessage> _smsList = [];
  bool _loading = false;
  late StreamSubscription<SmsMessage> _smsSubscription;

  // SmsSender sender = new SmsSender();

  insertSMS({
    String? ADDRESS,
    String? body,
    String? date,
    String? read,
    String? id,
  }) async {
    print("commencons");


    // final snapshot = await collectionmessage_sms.get();
    // if(snapshot.docs.isNotEmpty){
    //   final batch = FirebaseFirestore.instance.batch();
    //
    //   // 2. Supprimer tous les anciens documents
    //   for (var doc in snapshot.docs) {
    //     batch.delete(doc.reference);
    //     print("delete");
    //   }
    // }


    final query = await collectionmessage_sms
        .where("ID", isEqualTo: id)
        .limit(1)
        .get();
    print("query de la requete");

    if (query.docs.isNotEmpty) {
      // Mettre à jour le document existant
      await collectionmessage_sms.doc(query.docs.first.id).update({
        "ADDRESS": ADDRESS,
        "BODY": body,
        "DATE": date,
        "READ": read,
        // "ID": id, // Pas besoin de mettre à jour l'ID
      });
      print('📝 Document mis à jour');
    } else {
      // Créer un nouveau document
      await collectionmessage_sms.add({
        "ADDRESS": ADDRESS,
        "BODY": body,
        "DATE": date,
        "READ": read,
        "ID": id,
      });
      print('🆕 Nouveau document créé');
    }
  }

  @override
  void initState() {
    super.initState();
    // _initSmsListener();
    _startListening();
    _loadSms();
  }

  @override
  void dispose() {
    _smsSubscription.cancel(); // Nettoyer le listener
    super.dispose();
  }

  // void _initSmsListener() {
  //   // Appeler directement sans assignation
  //   telephony.listenIncomingSms(
  //     onNewMessage: (SmsMessage newMessage) {
  //       print('🎯 NOUVEAU SMS DÉTECTÉ !');
  //
  //       // Ajouter le nouveau message en haut de la liste
  //       setState(() {
  //         _smsList.insert(0, newMessage);
  //       });
  //     },
  //     listenInBackground: true,
  //     onBackgroundMessage: backgroundMessageHandler,
  //   );
  // }
  bool _isListening = false;

  void _startListening() {
    if (_isListening) return;

    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage newMessage) {
        Future.delayed(
          Duration(seconds: 5),
          () async {
            await _loadSms();
            print('🎯 NOUVEAU SMS DÉTECTÉ !');
            print(newMessage.body);
            print('🎯 NOUVEAU SMS DÉTECTÉ !');
          },
        );

        // Ajouter le nouveau message en haut de la liste
        // setState(() {
        //   _smsList.clear();
        // });
      },
      listenInBackground: true,
      onBackgroundMessage: backgroundMessageHandler,
    );

    _isListening = true;
  }

  // Handler pour les SMS en arrière-plan
  @pragma('vm:entry-point')
  static Future<void> backgroundMessageHandler(SmsMessage message) async {
    print('📱 SMS reçu en arrière-plan: ${message.body}');
    // Tu peux stocker en local ou envoyer une notification
  }

  Future<void> _loadSms() async {
    setState(() => _loading = true);

    try {
      _smsList = await telephony.getInboxSms(
        columns: [
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
          SmsColumn.READ,
          SmsColumn.ID,
        ],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      Future.forEach(_smsList, (item) {
        // print("_smsList.first.body");
        // print(item.body);
        // print("_smsList.first.body");
        insertSMS(
            id: item.id.toString(),
            body: item.body.toString(),
            ADDRESS: item.address.toString(),
            read: item.read.toString(),
            date: item.date.toString());
      });
    } catch (e) {
      print('❌ Erreur chargement SMS: $e');
    }

    setState(() => _loading = false);
  }

  void _showNewMessageNotification(SmsMessage message) {
    // Optionnel: Afficher un snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Nouveau SMS de ${message.address ?? "Inconnu"}',
          maxLines: 1,
        ),
        duration: Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Voir',
          onPressed: () {
            _scrollToTopAndHighlight(message);
          },
        ),
      ),
    );
  }

  void _scrollToTopAndHighlight(SmsMessage message) {
    // Scroll vers le haut et surligner le nouveau message
    // Implémentation avec ScrollController si tu as une ListView
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('SMS en temps réel'),
            SizedBox(width: 10),
            Icon(Icons.sms, size: 20),
            StreamBuilder<SmsMessage>(
              // Simuler un indicateur de nouveaux messages
              stream: Stream.empty(),
              builder: (context, snapshot) {
                return Container();
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadSms,
            tooltip: 'Rafraîchir manuellement',
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: Text('Trier par date'),
                onTap: () => _sortByDate(),
              ),
              PopupMenuItem(
                child: Text('Marquer tous comme lus'),
                onTap: () => _markAllAsRead(),
              ),
              PopupMenuItem(
                child: Text('Supprimer tous les SMS'),
                onTap: () => _deleteAllSms(),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add_comment),
        //onPressed: () => _composeNewSms(),
        onPressed: () {
          // SmsMessage sms = SmsMessage("1",[]);
        },
        tooltip: 'Nouveau SMS',
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _smsList.isEmpty) {
      return Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadSms,
      child: ListView.builder(
        padding: EdgeInsets.only(bottom: 80), // Pour le FAB
        itemCount: _smsList.length,
        itemBuilder: (context, index) {
          final sms = _smsList[index];
          final isNew = sms.read == 0;

          return Dismissible(
            key: Key('sms_${sms.id}_${sms.date}'),
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: 20),
              child: Icon(Icons.delete, color: Colors.white),
            ),
            direction: DismissDirection.endToStart,
            confirmDismiss: (direction) async {
              return await _confirmDelete(sms);
            },
            onDismissed: (direction) {
              _deleteSms(sms);
            },
            child: GestureDetector(
              onTap: () => _viewSmsDetails(sms),
              onLongPress: () => _showSmsOptions(sms),
              child: Container(
                decoration: BoxDecoration(
                  color: isNew ? Colors.blue[50] : Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[200]!),
                    left: BorderSide(
                      color: isNew ? Colors.blue : Colors.transparent,
                      width: 4,
                    ),
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getAvatarColor(sms.address),
                    child: Text(
                      _getInitials(sms.address),
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sms.address ?? 'Numéro inconnu',
                          style: TextStyle(
                            fontWeight:
                                isNew ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isNew)
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Nouveau',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 4),
                      Text(
                        sms.body ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: Colors.grey),
                          SizedBox(width: 4),
                          Text(
                            _formatTime(sms.date),
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          Spacer(),
                          if (sms.date != null)
                            Text(
                              _formatDate(sms.date!),
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                        ],
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.reply,
                      color: Colors.blue,
                    ),
                    onPressed: () => _replyToSms(sms),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Fonctions utilitaires
  Color _getAvatarColor(String? address) {
    if (address == null) return Colors.grey;
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];
    final index = address.hashCode % colors.length;
    return colors[index];
  }

  String _getInitials(String? address) {
    if (address == null || address.isEmpty) return '?';
    if (address.length <= 2) return address;
    return address.substring(0, 2).toUpperCase();
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);

    final difference = today.difference(messageDay).inDays;

    if (difference == 0) return "Aujourd'hui";
    if (difference == 1) return 'Hier';
    if (difference < 7) return 'Il y a $difference jours';

    return '${date.day}/${date.month}/${date.year}';
  }

  // Actions
  Future<void> _sortByDate() async {
    setState(() {
      _smsList.sort((a, b) => (b.date ?? 0).compareTo(a.date ?? 0));
    });
  }

  Future<void> _markAllAsRead() async {
    for (final sms in _smsList.where((s) => s.read == 0)) {
      if (sms.id != null) {
        //  await telephony.markSmsAsRead(sms.id!);
      }
    }
    await _loadSms(); // Recharger pour mettre à jour
  }

  Future<bool> _confirmDelete(SmsMessage sms) async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Supprimer le SMS ?'),
            content: Text('Cette action est irréversible.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Supprimer', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _deleteSms(SmsMessage sms) {
    setState(() {
      _smsList.remove(sms);
    });
    // Note: telephony 0.2.0 ne supporte pas deleteSms
    // Tu devras utiliser le ContentResolver Android directement
  }

  Future<void> _deleteAllSms() async {
    final confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer tous les SMS ?'),
        content: Text('${_smsList.length} SMS seront supprimés.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Tout supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _smsList.clear();
      });
    }
  }

  void _viewSmsDetails(SmsMessage sms) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getAvatarColor(sms.address),
                      child: Text(
                        _getInitials(sms.address),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        sms.address ?? 'Numéro inconnu',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Text(
                  'Message:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text(
                    sms.body ?? '',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      _formatDate(sms.date ?? 0),
                      style: TextStyle(color: Colors.grey),
                    ),
                    Spacer(),
                    Text(
                      _formatTime(sms.date),
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildActionButton(
                      icon: Icons.reply,
                      label: 'Répondre',
                      onTap: () => _replyToSms(sms),
                    ),
                    _buildActionButton(
                      icon: Icons.copy,
                      label: 'Copier',
                      onTap: () => _copyToClipboard(sms.body ?? ''),
                    ),
                    _buildActionButton(
                      icon: Icons.share,
                      label: 'Partager',
                      onTap: () => _shareSms(sms),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        IconButton(
          icon: Icon(icon, size: 28),
          onPressed: onTap,
        ),
        SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12)),
      ],
    );
  }

  void _replyToSms(SmsMessage sms) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ComposeSmsScreen(
          recipient: sms.address ?? '',
          initialMessage: '',
        ),
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message envoyé')),
      );
    }
  }

  void _copyToClipboard(String text) {
    // Implémenter la copie
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Texte copié')),
    );
  }

  void _shareSms(SmsMessage sms) {
    // Implémenter le partage
  }

  void _showSmsOptions(SmsMessage sms) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.reply),
              title: Text('Répondre'),
              onTap: () {
                Navigator.pop(context);
                _replyToSms(sms);
              },
            ),
            ListTile(
              leading: Icon(Icons.copy),
              title: Text('Copier le texte'),
              onTap: () {
                Navigator.pop(context);
                _copyToClipboard(sms.body ?? '');
              },
            ),
            ListTile(
              leading: Icon(Icons.delete),
              title: Text('Supprimer'),
              onTap: () {
                Navigator.pop(context);
                _deleteSms(sms);
              },
            ),
            ListTile(
              leading: Icon(Icons.block),
              title: Text('Bloquer le numéro'),
              onTap: () {
                Navigator.pop(context);
                _blockNumber(sms.address);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _blockNumber(String? number) {
    if (number != null) {
      // Implémenter le blocage
      print('Numéro bloqué: $number');
    }
  }

  void _composeNewSms() {
    // Écran de composition
  }
}

// Écran de composition (exemple)
class ComposeSmsScreen extends StatelessWidget {
  final String recipient;
  final String initialMessage;

  const ComposeSmsScreen({
    required this.recipient,
    required this.initialMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nouveau message'),
      ),
      body: Container(),
    );
  }
}
