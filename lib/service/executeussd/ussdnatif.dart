// lib/service/ussd_native_service.dart
import 'dart:async';
import 'package:flutter/services.dart';

class NativeUssdService {
  // Canaux - IMPORTANT: mêmes noms que dans Kotlin
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.ussd/native');

  static const EventChannel _responseChannel =
      EventChannel('com.example.ussd/responses');

  static const EventChannel _errorChannel =
      EventChannel('com.example.ussd/errors');

  // Singleton
  static final NativeUssdService _instance = NativeUssdService._internal();
  factory NativeUssdService() => _instance;
  NativeUssdService._internal();

  // Variables d'état
  bool _isInitialized = false;
  Stream<String>? _responseStream;
  Stream<String>? _errorStream;

  // Initialiser le service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {

      // 1. Tester la connexion d'abord
      await _methodChannel.invokeMethod('testConnection');

      // 2. Initialiser
      await _methodChannel.invokeMethod('initialize');

      _isInitialized = true;
    } on PlatformException {
      rethrow;
    }
  }

  // Envoyer un seul code USSD - MÉTHODE CORRIGÉE
  Future<String> sendSingleUssd({
    required String code,
    required int simSlot,
  }) async {
    try {

      final result = await _methodChannel.invokeMethod(
        'sendSingleUssd', // MÊME NOM QUE DANS KOTLIN
        {
          'code': code,
          'simSlot': simSlot,
        },
      );

      return result.toString();
    } on PlatformException catch (e) {

      // Erreur spécifique "MissingPluginException"
      if (e.code == 'MissingPluginException' ||
          e.message?.contains('No implementation found') == true) {
        throw Exception(
            "❌ La méthode 'sendSingleUssd' n'est pas implémentée dans le code natif.");
      }

      throw Exception("Erreur USSD: ${e.message}");
    }
  }

  // Envoyer une séquence USSD
  Future<void> sendUssdSequence({
    required List<String> codes,
    required int simSlot,
    int timeoutSeconds = 30,
  }) async {
    try {

      await _methodChannel.invokeMethod('sendUssdSequence', {
        'codes': codes,
        'simSlot': simSlot,
        'timeout': timeoutSeconds,
      });

    } on PlatformException {
      rethrow;
    }
  }

  // Obtenir les informations SIM
  Future<List<Map<String, dynamic>>> getSimInfo() async {
    try {

      final result = await _methodChannel.invokeMethod('getSimInfo');

      if (result is List) {
        final simCards = result.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return map;
        }).toList();

        return simCards;
      }

      return [];
    } on PlatformException {
      // Aucune SIM lisible : on rend une liste vide.
      return [];
    }
  }

  // Vérifier si USSD est supporté
  Future<bool> isUssdSupported() async {
    try {
      final result = await _methodChannel.invokeMethod('isUssdSupported');
      return result as bool;
    } on PlatformException {
      return false;
    }
  }

  // Tester la connexion
  Future<String> testConnection() async {
    try {
      final result = await _methodChannel.invokeMethod('testConnection');
      return result.toString();
    } on PlatformException catch (e) {
      return "❌ Erreur: ${e.message}";
    }
  }

  // Stream des réponses
  Stream<String> get responseStream {
    _responseStream ??=
        _responseChannel.receiveBroadcastStream().map((response) {
      return response.toString();
    }).handleError((error) {
      return "Erreur: $error";
    });

    return _responseStream!;
  }

  // Stream des erreurs
  Stream<String> get errorStream {
    _errorStream ??= _errorChannel.receiveBroadcastStream().map((error) {
      return error.toString();
    });

    return _errorStream!;
  }

  // Annuler la session
  Future<void> cancelSession() async {
    try {
      await _methodChannel.invokeMethod('cancelSession');
    } on PlatformException {
      // Rien à annuler côté natif.
    }
  }
}
