import 'package:flutter/services.dart';

class UssdStreamHandler {
  static const EventChannel _eventChannel =
      EventChannel('ussd_accessibility_stream');

  static Stream<String>? _eventStream;

  static Stream<String> get events {
    _eventStream ??=
        _eventChannel.receiveBroadcastStream().map((event) => event.toString());
    return _eventStream!;
  }

  static void dispose() {
    _eventStream = null;
  }
}
