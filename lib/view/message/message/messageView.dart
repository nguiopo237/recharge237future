import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:projettest/main.dart';
import 'package:projettest/view/message/PersonList.dart';
import 'package:sizer/sizer.dart';

import '../../../service/callapi/mail/api.dart';
import '../../../service/callapi/orange/generatepay.dart';
import '../../../service/controlleur/Reload_controlleur.dart';
import '../../../service/controlleur/transact_controlleur.dart';
import '../../../service/view/transact/transact_page.dart';

class ChatScreen extends StatefulWidget {
 Member? member;
  Transactions ?transaction;
   ChatScreen({super.key, this.member,this.transaction});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {

  final TextEditingController _messageController = TextEditingController();

  checkstatut() async {
print(widget.member?.name);

widget.member = Member(name: '3aa17372b03eddb1', status: 'EN LIGNE', lastSeen: '');

print(widget.member!.name);
   String data = await  r.detectOperator(widget.transaction?.category.toString());

    if(widget.transaction!=null&&widget.transaction?.statut=="0"&&data.contains("Orange")){
      print("verification avec orange");
      String statut =    await APIORANGE.getstatut(widget.transaction?.accesstoken,widget.transaction?.payToken,widget.transaction?.order);
 if(statut=="true"){
   print("verification avec orange");
   widget.transaction!.statut ="1";
   print("verification avec orange");
 }
    }else{

      final data = await APIORANGE.getMomoToken(init: false);
      if(data!=null){
        APIORANGE.getstatutMOMO(accesstoken: data ,subscriptionKey: "48f314fe512e4f99ab450cda504c5b26" ,targetEnv: "mtncameroon",XReferenceId:   widget.transaction?.payToken,);
        print("verification mtn");
        print(widget.transaction?.statut);
        print(widget.transaction?.category);
        print(data);
        // print(data);
        print("verification mtn");

      }

    }
  }

  ScrollController controller = ScrollController();

  void scrollToIndex() {
    const double itemHeight = 80.0;

    controller.animateTo(
      itemHeight * 60,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }


  @override
  void initState() {
    super.initState();

    if(widget.member==null){
      checkstatut();
    }

    scrollToIndex();
  }

  void _sendMessage() {

    if (_messageController.text.trim().isEmpty) return;

    collectionmessage_person.add({

    "id": "${idphone}${widget.transaction?.order??""}",
    "content":  _messageController.text,
    "timestamp":  DateTime.now().toUtc().toString(),
    "senderId": "${idphone}${widget.transaction?.order??""}",
    "receiveId": "${widget.member?.name.toString()}${widget.transaction?.order??""}",

    });

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {


    return Scaffold(
      appBar: AppBar(

        title:  Text(
         widget.member?.name??"admin",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.deepPurple[900],
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.deepPurple,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(height: 2.h,),
          if(widget.transaction!=null)
          t.buildTransactionItem(widget.transaction!),
          SizedBox(height: 1.h,),

          Expanded(
            child: StreamBuilder(
              stream:
              firestore
                  .collection('message')
                // .where("senderId", isEqualTo: idphone,)
               .orderBy("timestamp", descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Text('Erreur : ${snapshot.error}');
                } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Text('Pas de données disponibles');
                } else {
                  // Conversion correcte des documents en objets Messagemodel
                  final messages = snapshot.data!.docs.
                  where((element) {

                    checkifexist(){
                      return element["senderId"].toString()=="${idphone}${widget.transaction?.order??""}"
                          && element["receiveId"].toString()=="${widget.member?.name??"3aa17372b03eddb1"}${widget.transaction?.order??""}"
                          ||
                          element["senderId"].toString()=="${widget.member?.name??"3aa17372b03eddb1"}${widget.transaction?.order??""}";

                    }
                    checkifexist2(){
                      return element["senderId"].toString()=="${idphone}${widget.transaction?.order??""}"
                          && element["receiveId"].toString()=="${widget.member?.name??"3aa17372b03eddb1"}${widget.transaction?.order??""}"
                          ||
                          element["receiveId"].toString()!="${idphone}${widget.transaction?.order??""}"&&

                              element["senderId"].toString()=="${widget.member?.name??"3aa17372b03eddb1"}${widget.transaction?.order??""}";

                    }

                    return  widget.transaction!=null? checkifexist():checkifexist2();}).
                  map((doc) {
                    return Messagemodel(
                        content: doc["content"],
                        receiveId: doc["receiveId"],
                        senderId: doc["senderId"],
                        id: doc["id"],
                        
                        timestamp: DateTime.parse(doc["timestamp"]));
                  }).toList();
            
                  final messageGroups = MessageService.groupMessagesByDate(messages);

                  return Container(
                    child: ListView.builder(
                      reverse: false,
                      padding: const EdgeInsets.all(16),
                      itemCount: messageGroups.length,
                      itemBuilder: (context, groupIndex) {
                        final group = messageGroups[groupIndex];
            
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // En-tête de groupe de date
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  group.title,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Messages du groupe
                            ...group.messages.map((message) {
                              return MessageBubble(
                                message: message,
                                isMe: message.senderId == "${idphone}${widget.transaction?.order??""}",
                              );
                            }).toList(),
                          ],
                        );
                      },
                    ),
                  );
                }
              },
            ),
          ),


          // Expanded(
          //   child: Container(
          //     // color: Colors.orange,
          //     child: ListView.builder(
          //       reverse: true,
          //       padding: const EdgeInsets.all(16),
          //       itemCount: messageGroups.length,
          //       itemBuilder: (context, groupIndex) {
          //
          //         final group = messageGroups[groupIndex];
          //         return Column(
          //           crossAxisAlignment: CrossAxisAlignment.start,
          //
          //           children: [
          //             // En-tête de groupe de date
          //             Center(
          //               child: Container(
          //                 padding: const EdgeInsets.symmetric(
          //                   horizontal: 16,
          //                   vertical: 8,
          //                 ),
          //                 decoration: BoxDecoration(
          //                   color: Colors.grey[300],
          //                   borderRadius: BorderRadius.circular(16),
          //                 ),
          //                 child: Text(
          //                   group.title,
          //                   style: const TextStyle(
          //                     fontSize: 12,
          //                     fontWeight: FontWeight.w500,
          //                     color: Colors.black54,
          //                   ),
          //                 ),
          //               ),
          //             ),
          //             const SizedBox(height: 16),
          //             // Messages du groupe
          //             ...group.messages.map((message) {
          //               return MessageBubble(
          //                 message: message,
          //                 isMe: message.isMe,
          //               );
          //             }).toList(),
          //           ],
          //         );
          //       },
          //     ),
          //   ),
          // ),
          // Zone de saisie
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Tapez votre message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Messagemodel message;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe)
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey,
              child: Icon(Icons.person, size: 16, color: Colors.white),
            ),
          if (!isMe) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content.toString(),
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    MessageService.formatTime(message.timestamp!),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
          if (isMe)
        CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Icon(Icons.person, size: 16, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

// To parse this JSON data, do
//
//     final messagemodel = messagemodelFromJson(jsonString);



Messagemodel messagemodelFromJson(String str) => Messagemodel.fromJson(json.decode(str));

String messagemodelToJson(Messagemodel data) => json.encode(data.toJson());

class Messagemodel {
  String? content;
  String? id;
  String? receiveId;
  String? senderId;
  DateTime? timestamp;

  Messagemodel({
    this.content,
    this.id,
    this.receiveId,
    this.senderId,
    this.timestamp,
  });

  factory Messagemodel.fromJson(Map<String, dynamic> json) => Messagemodel(
    content: json["content"],
    id: json["id"],
    receiveId: json["receiveId"],
    senderId: json["senderId"],
    timestamp: json["timestamp"],
  );

  Map<String, dynamic> toJson() => {
    "content": content,
    "id": id,
    "receiveId": receiveId,
    "senderId": senderId,
    "timestamp": timestamp,
  };
}


class MessageGroup {
  final String title;
  final List<Messagemodel> messages;

  MessageGroup({
    required this.title,
    required this.messages,
  });
}


class MessageService {
  static List<MessageGroup> groupMessagesByDate(List<Messagemodel> messages) {
    messages.sort((a, b) => a.timestamp!.compareTo( b.timestamp!));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    Map<String, List<Messagemodel>> groupedMessages = {};

    for (var message in messages) {
      final messageDate = DateTime(
        message.timestamp!.year,
        message.timestamp!.month,
        message.timestamp!.day,
      );

      String groupTitle;

      if (messageDate == today) {
        groupTitle = "Aujourd'hui";
      } else if (messageDate == yesterday) {
        groupTitle = 'Hier';
      } else if (messageDate == tomorrow) {
        groupTitle = 'Demain';
      } else {
        groupTitle = _formatDate(messageDate);
      }

      if (!groupedMessages.containsKey(groupTitle)) {
        groupedMessages[groupTitle] = [];
      }
      groupedMessages[groupTitle]!.add(message);
    }

    return groupedMessages.entries.map((entry) {
      return MessageGroup(
        title: entry.key,
        messages: entry.value,
      );
    }).toList();
  }

  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  static String formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}