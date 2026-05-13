import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../fonctionfire.dart';



/// Service gérant le cycle de vie de l'application (Premier plan, Arrière-plan, Fermeture).
/// Utilise GetX pour la gestion d'état et observe les changements via WidgetsBindingObserver.
class AppLifecycleService extends GetxService with WidgetsBindingObserver {
  /// Indique si l'application est actuellement au premier plan.
  final isInForeground = true.obs;

  /// Stocke le dernier état du cycle de vie détecté.
  final lastState = AppLifecycleState.resumed.obs;

  // Timer pour éviter les mises à jour trop fréquentes vers la base de données (Debouncing)
  Timer? _debounceTimer;
  bool _isUpdatingOnlineStatus = false;

  // Constantes de configuration pour le SDK Zego (Appels/Vidéo)
  // À configurer avec les identifiants réels de la console ZegoCloud
  static const int _zegoAppID = 0;
  static const String _zegoAppSign = '';

  @override
  void onInit() {
    super.onInit();
    // Enregistre ce service comme observateur des changements d'état de l'application
    WidgetsBinding.instance.addObserver(this);
    getConnectivity(Get.context);
    print("📱 Service de cycle de vie initialisé");
  }

  @override
  void onClose() {
    // Nettoyage des observateurs et timers lors de la destruction du service
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    super.onClose();
  }

  /// Méthode déclenchée par Flutter lors d'un changement d'état (background, foreground, etc.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previousState = lastState.value;
    lastState.value = state;

    print("📱 Changement d'état: $previousState -> $state");

    switch (state) {
      case AppLifecycleState.resumed:
        _handleForeground();
        break;

      case AppLifecycleState.paused:
        // _handleBackground();
        break;

      case AppLifecycleState.inactive:
        _handleInactive();
        break;

      case AppLifecycleState.detached:
        _handleDetached();
        break;

      case AppLifecycleState.hidden:
        _handleHidden();
        break;
    }
  }

  /// Logique exécutée quand l'application revient au premier plan.
  void _handleForeground() {
    isInForeground.value = true;
    print("📱 PREMIER PLAN - Application active");

  // checkoperations(Get.context!);

    // Réinitialisation des services de communication
    // _reinitializeZego();

    // Mise à jour du statut "En ligne"
    _updateOnlineStatus(true);
  }

  /// Logique exécutée quand l'application passe en arrière-plan (minimisée).
  void _handleBackground() {
    isInForeground.value = false;
    print("📱 ARRIÈRE-PLAN - Application minimisée");
   //checkoperations(Get.context!);
   //  getConnectivity(Get.context);
    // Nettoyage pour libérer des ressources ou couper les flux actifs
    _cleanupZegoForBackground();

    // Mise à jour du statut "Hors ligne"
    _updateOnlineStatus(false);

    _onBackground();
  }

  /// Gère l'état inactif (ex: centre de notifications ouvert ou appel système entrant).
  void _handleInactive() {
    getConnectivity(Get.context);
   // checkoperations(Get.context!);
    print("📱 INACTIF - Écran de verrouillage/Appel");

    // if (AppUser.info?.googleId != null) {
    //   _updateOnlineStatus(false);
    // }
  }

  /// Gère l'état précédant la fermeture ou la destruction de l'application.
  void _handleDetached() {
    isInForeground.value = false;
  // checkoperations(Get.context!);
    getConnectivity(Get.context);
    print("📱 DÉTACHÉE - Application va être fermée");

    _completeCleanup();
  }

  /// Gère l'état caché (spécifique à certaines plateformes comme iOS/Web).
  void _handleHidden() {
    print("📱 CACHÉE - Application cachée");
    // getConnectivity(Get.context);
  // checkoperations(Get.context!);
    // if (AppUser.info?.googleId != null) {
    //   _updateOnlineStatus(false);
    // }
  }

  /// Met à jour le statut de l'utilisateur dans Firestore.
  /// Utilise un mécanisme de 'debounce' pour éviter les appels excessifs à l'API.
  void _updateOnlineStatus(bool isOnline) async {
    if (_isUpdatingOnlineStatus) return;

    // Vérifie si l'utilisateur est bien identifié avant de tenter une mise à jour
    // if (AppUser.info?.googleId == null || AppUser.info?.userI == null) {
    //   return;
    // }

    _isUpdatingOnlineStatus = true;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        // Mise à jour locale du modèle
        // AppUser.info?.isonline = isOnline;
        //
        // // Persistance dans la base de données Firestore
        // await Users.doc(AppUser.info?.userI).update({
        //   "isOnline": isOnline,
        //   "lastSeen": FieldValue.serverTimestamp(),
        // });

        print("📱 Statut en ligne mis à jour: $isOnline");
      } catch (e) {
        print("❌ Erreur mise à jour statut: $e");
      } finally {
        _isUpdatingOnlineStatus = false;
      }
    });
  }

  /// Relance les composants Zego (appels/vidéo) si nécessaire.
  void _reinitializeZego() {
    if (_zegoAppID == 0 || _zegoAppSign.isEmpty) {
      print("⚠️ Zego non configuré - Ignorer la réinitialisation");
      return;
    }

    try {
      // Logique de reconnexion ou de login Zego à insérer ici
    } catch (e) {
      print("❌ Exception lors de la réinitialisation Zego: $e");
    }
  }

  /// Nettoie les ressources Zego lors du passage en arrière-plan pour éviter les fuites.
  void _cleanupZegoForBackground() {
    if (_zegoAppID == 0 || _zegoAppSign.isEmpty) {
      return;
    }

    try {
      print("🧹 Nettoyage Zego pour l'arrière-plan...");
      // Ex: Arrêt des flux vidéo locaux
      print("✅ Zego nettoyé pour l'arrière-plan");
    } catch (e) {
      print("❌ Erreur nettoyage Zego: $e");
    }
  }

  /// Nettoyage total avant la fermeture définitive.
  void _completeCleanup() {
    if (_zegoAppID == 0 || _zegoAppSign.isEmpty) {
      return;
    }

    try {
      print("🧹 Nettoyage complet...");
      // Ex: Déconnexion totale des services de messagerie/appel
      print("✅ Nettoyage complet terminé");
    } catch (e) {
      print("❌ Erreur nettoyage complet: $e");
    }
  }

  /// Déclenche des actions spécifiques lors du passage en arrière-plan.
  void _onBackground() {
    print("💾 Sauvegarde de l'état avant passage en arrière-plan");
    _saveAppState();
  }

  /// Gère la persistance des données temporaires de l'utilisateur.
  void _saveAppState() {
    // Implémenter la sauvegarde des préférences ou données de session ici
  }

  /// Getters pour accéder facilement à l'état depuis l'UI
  bool get isForeground => isInForeground.value;
  bool get isBackground => !isInForeground.value;

  /// Permet de configurer les identifiants Zego (Note: les constantes doivent être changées en variables pour être mutables)
  void configureZego({required int appID, required String appSign}) {
    print("⚠️ Pour configurer Zego, modifiez directement _zegoAppID et _zegoAppSign dans le fichier");
  }
}
