import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

import '../../main.dart';
import 'message/messageView.dart';

class MemberListScreen extends StatefulWidget {
  @override
  _MemberListScreenState createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> {
  // Liste d'exemple des membres
  final List<Member> members = [
    Member(name: 'Alice Dubois', status: 'En ligne', lastSeen: 'Maintenant'),
    Member(
        name: 'Bernard Martin', status: 'Hors ligne', lastSeen: 'Il y a 2 min'),
    Member(name: 'Claire Petit', status: 'En ligne', lastSeen: 'Maintenant'),
    Member(name: 'David Leroy', status: 'Occupé', lastSeen: 'Il y a 5 min'),
    Member(name: 'Emma Laurent', status: 'En ligne', lastSeen: 'Maintenant'),
    Member(
        name: 'François Moreau',
        status: 'Hors ligne',
        lastSeen: 'Il y a 10 min'),
    Member(name: 'Gabrielle Simon', status: 'En ligne', lastSeen: 'Maintenant'),
    Member(name: 'Hugo Michel', status: 'Absent', lastSeen: 'Il y a 1 heure'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Liste des Membres',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: Colors.white),
            onPressed: () {
              // Action de recherche
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.deepPurple.withOpacity(0.1),
              Colors.purple.withOpacity(0.05),
            ],
          ),
        ),
        child: Column(
          children: [
            // En-tête avec statistiques
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'En ligne',
                    members
                        .where((m) => m.status == 'En ligne')
                        .length
                        .toString(),
                    Colors.green,
                  ),
                  _buildStatItem(
                    'Total',
                    members.length.toString(),
                    Colors.deepPurple,
                  ),
                  _buildStatItem(
                    'Hors ligne',
                    members
                        .where((m) => m.status == 'Hors ligne')
                        .length
                        .toString(),
                    Colors.grey,
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),

            Container(
              child: StreamBuilder(
                stream: firestore
                    .collection('member')
                    .where("idphone", isNotEqualTo: idphone)
                    // .orderBy("heure", descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Text('Erreur : ${snapshot.error}');
                  } else if (!snapshot.hasData) {
                    return Text('Pas de données disponibles');
                  } else {
                    // scrollToIndex1();
                    final itemdata = snapshot.data?.docs;
                    return ListView.builder(
                      shrinkWrap: true,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: itemdata!.length,
                      itemBuilder: (context, index) {
                        final group = itemdata[index];
                        final item = Member(
                            name: group["idphone"],
                            status: group["statut"].toString(),
                            lastSeen: 'sdsd');
                        return _buildMemberCard(item, index);
                      },
                    );
                  }
                },
              ),
            ),

            // Liste des membres
            // Expanded(
            //   child: ListView.builder(
            //     itemCount: members.length,
            //     itemBuilder: (context, index) {
            //       final member = members[index];
            //       return _buildMemberCard(member, index);
            //     },
            //   ),
            // ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Action pour ajouter un membre
        },
        backgroundColor: Colors.purple,
        child: Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  Widget _buildStatItem(String title, String value, Color color) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            color: Colors.deepPurple,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildMemberCard(Member member, int index) {
    // Alternance des couleurs pour un effet visuel agréable
    final Color primaryColor = index.isEven ? Colors.deepPurple : Colors.purple;
    final bool isOnline = member.status == 'En ligne';

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: primaryColor,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              member.name.substring(0, 1),
              style: TextStyle(
                color: primaryColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Text(
          member.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.deepPurple[900],
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              member.status,
              style: TextStyle(
                color: _getStatusColor(member.status),
                fontSize: 12,
              ),
            ),
            Text(
              member.lastSeen,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 10,
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isOnline
                ? Colors.green.withOpacity(0.2)
                : Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 4),
              Text(
                isOnline ? 'En ligne' : 'Hors ligne',
                style: TextStyle(
                  fontSize: 10,
                  color: isOnline ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        onTap: () {
          // Action lorsqu'on clique sur un membre
          // _showMemberDetails(member);
          Get.to(ChatScreen(
            member: member,
          ));
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'En ligne':
        return Colors.green;
      case 'Hors ligne':
        return Colors.grey;
      case 'Occupé':
        return Colors.orange;
      case 'Absent':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showMemberDetails(Member member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  member.name.substring(0, 1),
                  style: TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                member.name,
                style: TextStyle(
                  color: Colors.deepPurple[900],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Statut: ${member.status}',
              style: TextStyle(
                color: _getStatusColor(member.status),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Dernière connexion: ${member.lastSeen}',
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Fermer',
              style: TextStyle(color: Colors.deepPurple),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // Action pour envoyer un message
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
            child: Text(
              'Message',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class Member {
  String name;
  final String status;
  final String lastSeen;
  final String? isadmin;

  Member({
    required this.name,
    required this.status,
    required this.lastSeen,
    this.isadmin,
  });
}

// Pour utiliser cette interface, ajoutez ceci dans votre main.dart :
/*
void main() {
  runApp(MaterialApp(
    home: MemberListScreen(),
    theme: ThemeData(
      primaryColor: Colors.deepPurple,
      colorScheme: ColorScheme.fromSwatch().copyWith(
        secondary: Colors.purple,
      ),
    ),
  ));
}
*/
