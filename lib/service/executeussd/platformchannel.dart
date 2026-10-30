// lib/service/ussd_native_service.dart
import 'dart:async';
import 'package:flutter/services.dart';

class NativeUssdService {
  static const MethodChannel _channel =
      MethodChannel('com.example.ussd/native');
  static const EventChannel _responseChannel =
      EventChannel('com.example.ussd/responses');
  static const EventChannel _errorChannel =
      EventChannel('com.example.ussd/errors');

  Stream<String>? _responseStream;
  Stream<String>? _errorStream;

  // Singleton pattern
  static final NativeUssdService _instance = NativeUssdService._internal();
  factory NativeUssdService() => _instance;
  NativeUssdService._internal();

  // Initialiser le service
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
    } on PlatformException catch (e) {
      print("Erreur d'initialisation: ${e.message}");
    }
  }

  // Envoyer une séquence USSD
  Future<void> sendUssdSequence({
    required List<String> codes,
    required int simSlot,
    int timeoutSeconds = 30,
  }) async {
    try {
      print("Début de la session USSD native");

      final Map<String, dynamic> params = {
        'codes': codes,
        'simSlot': simSlot,
        'timeout': timeoutSeconds,
      };

      await _channel.invokeMethod('sendUssdSequence', params);
    } on PlatformException catch (e) {
      print("Erreur PlatformException: ${e.message}");
      throw Exception("Erreur USSD native: ${e.message}");
    }
  }

  // Envoyer un code USSD simple
  Future<String> sendSingleUssd({
    required String code,
    required int simSlot,
  }) async {
    try {
      final result = await _channel.invokeMethod('sendSingleUssd', {
        'code': code,
        'simSlot': simSlot,
      });
      return result.toString();
    } on PlatformException catch (e) {
      throw Exception("Erreur USSD: ${e.message}");
    }
  }

  // Obtenir le stream des réponses
  Stream<String> get responseStream {
    _responseStream ??= _responseChannel
        .receiveBroadcastStream()
        .map((response) => response.toString());
    return _responseStream!;
  }

  // Obtenir le stream des erreurs
  Stream<String> get errorStream {
    _errorStream ??=
        _errorChannel.receiveBroadcastStream().map((error) => error.toString());
    return _errorStream!;
  }

  // Annuler la session en cours
  Future<void> cancelSession() async {
    try {
      await _channel.invokeMethod('cancelSession');
    } on PlatformException catch (e) {
      print("Erreur d'annulation: ${e.message}");
    }
  }

  // Vérifier si USSD est supporté
  Future<bool> isUssdSupported() async {
    try {
      final result = await _channel.invokeMethod('isUssdSupported');
      return result as bool;
    } on PlatformException catch (e) {
      print("Erreur vérification support: ${e.message}");
      return false;
    }
  }

  // Obtenir les informations SIM
  Future<List<Map<String, dynamic>>> getSimInfo() async {
    try {
      final result = await _channel.invokeMethod('getSimInfo');
      return List<Map<String, dynamic>>.from(result as List);
    } on PlatformException catch (e) {
      print("Erreur obtention infos SIM: ${e.message}");
      return [];
    }
  }
}
