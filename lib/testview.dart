// import 'package:flutter/material.dart';
// import 'package:projettest/service/controlleur/home_controlleur.dart';
// import 'package:projettest/service/controlleur/homp.dart';
// import 'package:projettest/service/permission.dart';
//
// class SmsDisplayWidget extends StatefulWidget {
//   @override
//   _SmsDisplayWidgetState createState() => _SmsDisplayWidgetState();
// }
//
// class _SmsDisplayWidgetState extends State<SmsDisplayWidget> {
//   Homecontolleurs _controller = Homecontolleurs();
//   String _lastMessage = "Aucun message intercepté";
//
//   @override
//   void initState() {
//     super.initState();
//     PermissionHelper.requestSmsPermission();
//     _controller.initializeSmsListener(
//         onCodeCallback: (code) {
//           setState(() {
//             _lastMessage = "Dernier code: $code (${DateTime.now().toString()})";
//           });
//         }
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Intercepteur SMS'),
//         backgroundColor: Colors.blue,
//       ),
//       body: Padding(
//         padding: EdgeInsets.all(20.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             // Carte d'information
//             Card(
//               elevation: 5,
//               child: Padding(
//                 padding: EdgeInsets.all(20.0),
//                 child: Column(
//                   children: [
//                     Icon(
//                       Icons.sms,
//                       size: 50,
//                       color: Colors.blue,
//                     ),
//                     SizedBox(height: 10),
//                     Text(
//                       'Statut: Écoute active',
//                       style: TextStyle(
//                         fontSize: 16,
//                         fontWeight: FontWeight.bold,
//                         color: Colors.green,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//
//             SizedBox(height: 30),
//
//             // Affichage du dernier message
//             Container(
//               width: double.infinity,
//               padding: EdgeInsets.all(15),
//               decoration: BoxDecoration(
//                 color: Colors.grey[100],
//                 borderRadius: BorderRadius.circular(10),
//                 border: Border.all(color: Colors.grey[300]!),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'Dernier message:',
//                     style: TextStyle(
//                       fontWeight: FontWeight.bold,
//                       fontSize: 16,
//                     ),
//                   ),
//                   SizedBox(height: 10),
//                   Text(
//                     _lastMessage,
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: Colors.grey[800],
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//
//             SizedBox(height: 30),
//
//             // Bouton pour afficher dans la console
//             ElevatedButton.icon(
//               onPressed: () {
//                 _controller.displayLastMessage();
//                 setState(() {
//                   if (_controller.lastCode != null) {
//                     _lastMessage = "Code: ${_controller.lastCode} - ${_controller.lastTimestamp}";
//                   }
//                 });
//               },
//               icon: Icon(Icons.message),
//               label: Text('Afficher dernier SMS dans la console'),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: Colors.orange,
//                 foregroundColor: Colors.white,
//                 padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
//               ),
//             ),
//
//             SizedBox(height: 15),
//
//             // Bouton pour effacer l'historique
//             ElevatedButton.icon(
//               onPressed: () {
//                 setState(() {
//                   _lastMessage = "Aucun message intercepté";
//                 });
//                 print("🗑️ Historique effacé");
//               },
//               icon: Icon(Icons.clear),
//               label: Text('Effacer l\'affichage'),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: Colors.red,
//                 foregroundColor: Colors.white,
//               ),
//             ),
//           ],
//         ),
//       ),
//
//       // Bouton flottant pour accès rapide
//       floatingActionButton: FloatingActionButton(
//         onPressed: () {
//           _controller.displayLastMessage();
//         },
//         child: Icon(Icons.sms),
//         backgroundColor: Colors.blue,
//         tooltip: 'Afficher dernier SMS',
//       ),
//     );
//   }
//
//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }
// }


