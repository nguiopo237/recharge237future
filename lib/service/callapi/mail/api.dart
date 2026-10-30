// import 'package:another_telephony/telephony.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';

class API {
  static Future<void> sendEmail(
      {String? amount,
      String? numeroc,
      // SmsMessage ?sms,
      String? idtransact,
      String? subject = "",
      String? body}) async {
    // Validation des adresses
    String fromEmail = "camillenguiopo@gmail.com";
    String toEmail = "recharge2370@gmail.com";
    String? username = 'camillenguiopo@gmail.com';
    String password = 'wyha qkhy guca hqif';
    body =
        "salue nous avons tranferer le credit de $amount  au numero suivant $numeroc voici le numero transact $idtransact ,le contenue du sms est le suivant : ${null == null ? "pas de sms" : "sms.body"}";

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(fromEmail) ||
        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(toEmail)) {
      throw ArgumentError('Format d\'email invalide');
    }

    final smtpServer = gmail(username, password);
    final message = Message()
      ..from = Address(fromEmail, 'camille')
      ..recipients.add(Address(toEmail, 'Recharge 237'))
      ..subject = subject
      ..html = body;

    try {
      final sendReport = await send(message, smtpServer);
      print('Email envoyé avec succès: ${sendReport.toString()}');
    } catch (e) {
      print('Erreur lors de l\'envoi: $e');
      rethrow;
    }
  }
}
