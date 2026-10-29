package com.example.projettest

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.ServiceState
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import com.kavina.ussd_launcher.UssdAccessibilityService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal `r237/ussd` : pilotage USSD étape par étape (lib/service/ussd/ussd_session.dart).
 *
 * Le plugin ussd_launcher capte les écrans USSD (service d'accessibilité) et
 * les envoie à Dart. Son mode multi-étapes répond à délai fixe sans lire les
 * écrans : on ne l'utilise plus. Ici :
 *  - dial   : compose le code sur la SIM demandée (dialogues USSD visibles) ;
 *  - reply  : tape UNE réponse dans le dialogue affiché et valide ;
 *  - cancel : ferme le dialogue USSD affiché ;
 *  - serviceReady : le service d'accessibilité du plugin est connecté.
 *
 * Canal `sims` : inventaire du matériel du téléphone (modèle + SIM actives
 * avec opérateur et emplacement). Écrit ensuite dans `servers/{deviceId}`
 * par ServerManager, pour que l'admin n'ait plus à saisir les emplacements.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // [28/10/2026] Écran maintenu allumé tant que le serveur est au premier
        // plan : quand le téléphone se verrouille, MIUI n'affiche que le TITRE
        // du dialogue USSD (« MTN Mobile Money ») sans son contenu, si bien
        // qu'aucune réponse ne peut être lue ni saisie et que la session
        // expire (constaté le 28/10 à 04:11 sur une commande de 106 F).
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // [VEILLE 28/10/2026] Verrou d'éveil permanent du serveur.
        //
        // Constaté le 28/10 à 19:24 : téléphone sur batterie, écran éteint,
        // processus VIVANT (PID inchangé) mais totalement figé par MIUI — plus
        // aucun battement, plus aucune commande traitée, plus aucun contrôle
        // réseau. Le service de premier plan et l'autorisation batterie ne
        // suffisaient pas.
        //
        // Un verrou PARTIEL garde le processeur éveillé sans allumer l'écran :
        // les minuteries Dart continuent de tourner écran éteint, ce qui est
        // exactement le besoin d'un serveur de livraison. Il est pris une fois
        // au démarrage et rendu à la destruction de l'activité.
        acquireServerWakeLock()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "r237/ussd")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "dial" -> {
                            val code = call.argument<String>("code") ?: ""
                            val slot = call.argument<Int>("slot") ?: 0
                            if (code.isEmpty()) {
                                result.error("EMPTY_CODE", "Code USSD vide", null)
                            } else {
                                // Dialogues visibles : le mode "masqué" du plugin
                                // appuie sur Retour à chaque nouvelle fenêtre.
                                UssdAccessibilityService.hideDialogs = false
                                UssdAccessibilityService.resetLastMessage()
                                // [ISOLEMENT 28/10/2026] Avant d'injecter quoi que
                                // ce soit : réveil, déverrouillage, écran nettoyé
                                // des autres applications, app serveur seule au
                                // premier plan. Le nettoyage fait des pauses
                                // (actions globales d'accessibilité) : il tourne
                                // donc hors du thread principal, sinon l'app se
                                // figerait pendant la préparation.
                                wakeForSession()
                                Thread {
                                    try {
                                        UssdAccessibilityService.clearForeignWindows()
                                    } catch (_: Exception) {
                                    }
                                    runOnUiThread {
                                        try {
                                            bringToFront()
                                            // placeCall() passe par le service
                                            // télécom : il fonctionne même en
                                            // arrière-plan (Android 10+ interdit
                                            // de démarrer une activité depuis
                                            // l'arrière-plan). startActivity en
                                            // secours seulement s'il refuse.
                                            if (!placeCall(code, slot)) {
                                                startActivity(callIntent(code, slot))
                                            }
                                            result.success(true)
                                        } catch (e: Exception) {
                                            result.error("USSD_NATIVE", e.message, null)
                                        }
                                    }
                                }.start()
                            }
                        }
                        "reply" -> {
                            val text = call.argument<String>("text") ?: ""
                            UssdAccessibilityService.sendReply(listOf(text))
                            result.success(true)
                        }
                        "cancel" -> {
                            // true = une fenêtre USSD a été trouvée et fermée
                            // (bouton « Annuler »/« OK » cliqué), false = rien
                            // à fermer.
                            result.success(UssdAccessibilityService.cancelSession())
                        }
                        "serviceReady" -> result.success(UssdAccessibilityService.isServiceRunning())
                        "sims" -> result.success(describeHardware())
                        "serviceState" -> {
                            val slot = call.argument<Int>("slot") ?: 0
                            result.success(describeServiceState(slot))
                        }
                        "airplaneProbe" -> {
                            // [RESEAU 28/10/2026] Sonde SANS RISQUE : repère la
                            // tuile « Mode avion » du tiroir de réglages rapides
                            // et lit son état, sans la toucher. Permet de vérifier
                            // que le pilotage par l'écran est possible avant de
                            // couper la radio d'un téléphone de production.
                            Thread {
                                val trouve = try {
                                    UssdAccessibilityService.setAirplaneTile(false, sonde = true)
                                } catch (e: Exception) {
                                    false
                                }
                                runOnUiThread { result.success(trouve) }
                            }.start()
                        }
                        "radioCycle" -> {
                            // [RESEAU 28/10/2026] Cycle court (<= 2 min) pour
                            // forcer une nouvelle inscription réseau quand une
                            // carte reste des heures en « appels d'urgence
                            // uniquement ». Exécuté hors du thread principal :
                            // il attend réellement entre les deux états.
                            val slot = call.argument<Int>("slot") ?: 0
                            val onMs = (call.argument<Int>("onMs") ?: 35000).toLong()
                            val waitMs = (call.argument<Int>("waitMs") ?: 40000).toLong()
                            Thread {
                                val out = try {
                                    airplaneCycle(slot, onMs, waitMs)
                                } catch (e: Exception) {
                                    mapOf("attempted" to false, "detail" to (e.message ?: "erreur native"))
                                }
                                runOnUiThread { result.success(out) }
                            }.start()
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("USSD_NATIVE", e.message, null)
                }
            }
    }

    /**
     * [RESEAU 28/10/2026] Cycle « mode avion » court, vérifié, et sans laisser
     * le téléphone sans réseau.
     *
     * Pourquoi : une SIM peut rester des heures en « appels d'urgence
     * uniquement » alors que le réseau existe — la carte ne se ré-inscrit pas
     * toute seule. Constaté en production les 27 et 28/10 sur la SIM MTN.
     *
     * Règles appliquées, exactement comme demandé par l'admin :
     *  - le cycle complet tient en MOINS de 2 minutes (35 s coupé + 40 s
     *    d'attente d'inscription) ;
     *  - le Wi-Fi et les données mobiles sont relevés AVANT, puis remis dans
     *    l'état où ils étaient APRÈS : on ne laisse jamais l'appareil sans
     *    internet, sinon il ne peut plus lire la base ni recevoir d'ordres ;
     *  - l'effet est VÉRIFIÉ : si l'état radio n'a pas bougé, on le dit au lieu
     *    de prétendre avoir agi (Android 11+ réserve le basculement aux
     *    applications système ; l'écriture n'agit que si le téléphone accorde
     *    WRITE_SECURE_SETTINGS, cf. script d'installation).
     */
    private fun airplaneCycle(slot: Int, onMs: Long, waitMs: Long): Map<String, Any> {
        val debut = System.currentTimeMillis()
        val avant = radioSnapshot()
        val precedent = describeServiceState(slot)

        // 1. Voie normale : écrire le réglage (nécessite WRITE_SECURE_SETTINGS).
        val ecrit = applyAirplaneMode(true)
        Thread.sleep(1500)
        var methode = "reglage"
        // 2. Android 11+ ignore souvent cette écriture : on bascule alors par
        //    l'écran, comme le ferait un humain (tuile « Mode avion »).
        if (radioSnapshot()["airplane"] != true) {
            val parEcran = try {
                UssdAccessibilityService.setAirplaneTile(true)
            } catch (_: Exception) {
                false
            }
            methode = if (parEcran) "ecran" else "refuse"
            Thread.sleep(1200)
        }

        Thread.sleep(onMs.coerceIn(5000L, 60000L))
        val coupe = describeServiceState(slot)

        // Retour obligatoire : réglage d'abord, écran ensuite s'il a servi.
        applyAirplaneMode(false)
        Thread.sleep(800)
        if (radioSnapshot()["airplane"] == true) {
            try {
                UssdAccessibilityService.setAirplaneTile(false)
            } catch (_: Exception) {
            }
            Thread.sleep(1000)
        }

        // Restauration immédiate de ce qui était actif avant le cycle.
        var wifiRendu = true
        if (avant["wifi"] == true) wifiRendu = enableWifi(true)
        if (avant["mobileData"] == true) enableMobileData(true)

        Thread.sleep(waitMs.coerceIn(5000L, 75000L))
        val apres = radioSnapshot()
        val etat = describeServiceState(slot)

        // Dernier filet : si le Wi-Fi était allumé et ne l'est plus, on réessaie.
        if (avant["wifi"] == true && apres["wifi"] != true) {
            enableWifi(true)
            Thread.sleep(1500)
        }
        val final = radioSnapshot()

        val radioBouge = (coupe["stateLabel"] ?: "") != (precedent["stateLabel"] ?: "") ||
            (final["airplane"] ?: false) != (avant["airplane"] ?: false) ||
            (coupe["airplane"] ?: false) != (avant["airplane"] ?: false)

        return mapOf(
            "attempted" to true,
            "wrote" to ecrit,
            "radioChanged" to radioBouge,
            "before" to avant,
            "after" to final,
            "serviceBefore" to (precedent["stateLabel"] ?: ""),
            "serviceDuring" to (coupe["stateLabel"] ?: ""),
            "serviceAfter" to (etat["stateLabel"] ?: ""),
            "wifiRestored" to (final["wifi"] == avant["wifi"]),
            "dataRestored" to (final["mobileData"] == avant["mobileData"]),
            "method" to methode,
            "elapsedMs" to (System.currentTimeMillis() - debut),
        )
    }

    /** État radio + réseau de l'appareil (avant/après comparaison). */
    private fun radioSnapshot(): Map<String, Any> {
        val airplane = try {
            Settings.Global.getInt(contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0) == 1
        } catch (_: Exception) {
            false
        }
        val wifi = try {
            (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager).isWifiEnabled
        } catch (_: Exception) {
            false
        }
        val data = try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) tm.isDataEnabled else true
        } catch (_: Exception) {
            true
        }
        return mapOf("airplane" to airplane, "wifi" to wifi, "mobileData" to data)
    }

    /** Basculle le mode avion. `false` = le téléphone a refusé l'écriture. */
    private fun applyAirplaneMode(on: Boolean): Boolean {
        return try {
            Settings.Global.putInt(
                contentResolver,
                Settings.Global.AIRPLANE_MODE_ON,
                if (on) 1 else 0
            )
            val intent = Intent(Intent.ACTION_AIRPLANE_MODE_CHANGED)
            intent.putExtra("state", on)
            intent.setPackage("android")
            sendBroadcast(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun enableWifi(on: Boolean): Boolean {
        return try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wm.setWifiEnabled(on)
        } catch (_: Exception) {
            false
        }
    }

    private fun enableMobileData(on: Boolean) {
        try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                tm.setDataEnabled(on)
            }
        } catch (_: Exception) {
            // Réservé aux applications système sur les Android récents : le mode
            // avion a déjà rétabli les données par lui-même dans ce cas.
        }
    }

    private var serverWakeLock: PowerManager.WakeLock? = null

    /** Verrou d'éveil du serveur (processeur, écran libre de s'éteindre). */
    private fun acquireServerWakeLock() {
        if (serverWakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            serverWakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "r237:serveur-us"
            ).apply {
                setReferenceCounted(false)
                // Sans échéance : c'est un serveur, il doit tourner tant que
                // l'application est vivante. Le verrou tombe avec le processus.
                acquire()
            }
        } catch (e: Exception) {
            android.util.Log.w("r237", "verrou d'éveil refusé : ${e.message}")
        }
    }

    private fun releaseServerWakeLock() {
        try {
            if (serverWakeLock?.isHeld == true) serverWakeLock?.release()
        } catch (_: Exception) {
        }
        serverWakeLock = null
    }

    override fun onDestroy() {
        releaseServerWakeLock()
        super.onDestroy()
    }

    private var sessionWakeLock: PowerManager.WakeLock? = null

    /**
     * Réveille l'écran et garde le CPU éveillé pendant une session USSD.
     *
     * Constaté le 28/10 à 05:03 : `mWakefulness=Dozing`, la commande est
     * restée bloquée en « en cours » sans qu'aucun écran d'opérateur
     * n'apparaisse. Le verrou expire seul au bout de 4 minutes : aucune
     * batterie ne reste consommée si l'app est tuée en pleine session.
     */
    private fun wakeForSession() {
        try {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        } catch (_: Exception) {
        }
        // [ISOLEMENT 28/10/2026] Écran verrouillé = le dialogue USSD s'affiche
        // sans son contenu. On demande l'affichage par-dessus le verrou et le
        // déverrouillage automatique (sans code depuis que le verrou a été
        // retiré ; sinon Android demande simplement le code).
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            } else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                )
            }
        } catch (_: Exception) {
        }
        try {
            val km = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            if (km.isKeyguardLocked) {
                km.requestDismissKeyguard(this, null)
            }
        } catch (_: Exception) {
        }
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            sessionWakeLock?.let { if (it.isHeld) it.release() }
            @Suppress("DEPRECATION")
            val lock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "r237:ussd-session"
            )
            lock.acquire(4 * 60 * 1000L)
            sessionWakeLock = lock
        } catch (_: Exception) {
        }
    }

    /**
     * Ramène l'app serveur seule au premier plan.
     *
     * Android 10+ bloque le démarrage d'une activité depuis l'arrière-plan
     * sauf privilège particulier : l'échec est normal et sans conséquence, la
     * session USSD partant de toute façon par le service télécom.
     */
    private fun bringToFront() {
        try {
            startActivity(
                Intent(this, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            )
        } catch (_: Exception) {
        }
    }

    /**
     * État du réseau mobile pour la SIM [slot].
     *
     * [28/10/2026] Constaté sur le téléphone de production : SIM
     * `OUT_OF_SERVICE` (aucune couverture MTN). L'USSD partait quand même,
     * l'opérateur répondait « Problème de connexion ou code IHM non valide »
     * après plusieurs minutes, et la commande restait bloquée « en cours ».
     * Mieux vaut refuser en une seconde, en disant pourquoi.
     */
    private fun describeServiceState(slot: Int): Map<String, Any?> {
        // [RESEAU 28/10/2026] Mode avion : aucune session USSD ne peut aboutir,
        // quel que soit l'opérateur. On le dit au lieu de laisser expirer.
        val airplane = try {
            android.provider.Settings.Global.getInt(
                contentResolver,
                android.provider.Settings.Global.AIRPLANE_MODE_ON, 0
            ) == 1
        } catch (_: Exception) {
            false
        }
        return try {
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val info = sm.getActiveSubscriptionInfoForSimSlotIndex(slot)
                ?: return mapOf(
                    "known" to true,
                    "registered" to false,
                    "emergencyOnly" to false,
                    "airplaneMode" to airplane,
                    "simState" to "ABSENT",
                    "carrier" to "",
                    "operator" to "",
                    "mccMnc" to "",
                    "signalLevel" to 0,
                    "stateLabel" to "ABSENT",
                    "detail" to "aucune SIM dans l'emplacement ${slot + 1}"
                )
            val tm = (getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager)
                .createForSubscriptionId(info.subscriptionId)
            val simState = try {
                tm.simState
            } catch (_: Exception) {
                TelephonyManager.SIM_STATE_UNKNOWN
            }
            val ss: ServiceState? = tm.serviceState
            // Signal : 0 à 4. API 28 minimum pour SignalStrength.getLevel().
            val level = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    tm.signalStrength?.level ?: -1
                } catch (_: Exception) {
                    -1
                }
            } else {
                -1
            }
            val carrier = try {
                info.carrierName?.toString() ?: ""
            } catch (_: Exception) {
                ""
            }
            val simOperator = try {
                tm.simOperator ?: ""
            } catch (_: Exception) {
                ""
            }
            mapOf(
                // `known = false` : Android n'a pas su répondre. Côté Dart on
                // ne refuse pas sur cette base (mieux vaut tenter).
                "known" to (ss != null),
                "registered" to (ss?.state == ServiceState.STATE_IN_SERVICE),
                // `ServiceState.isEmergencyOnly()` n'est pas dans le SDK
                // public : seul l'état global est exploitable ici. Le cas
                // « appels d'urgence seulement » ressort donc comme
                // OUT_OF_SERVICE, ce qui est déjà un refus correct.
                "emergencyOnly" to (ss?.state == ServiceState.STATE_EMERGENCY_ONLY),
                "airplaneMode" to airplane,
                "simState" to simStateName(simState),
                "carrier" to carrier,
                "operator" to (ss?.operatorAlphaLong ?: ""),
                "mccMnc" to simOperator,
                "signalLevel" to level,
                "stateLabel" to serviceStateName(ss?.state ?: ServiceState.STATE_OUT_OF_SERVICE),
                "detail" to ""
            )
        } catch (e: Exception) {
            mapOf(
                "known" to false,
                "registered" to false,
                "emergencyOnly" to false,
                "airplaneMode" to airplane,
                "simState" to "UNKNOWN",
                "carrier" to "",
                "operator" to "",
                "mccMnc" to "",
                "signalLevel" to -1,
                "stateLabel" to "UNKNOWN",
                "detail" to (e.javaClass.simpleName + ": " + (e.message ?: "etat inconnu"))
            )
        }
    }

    private fun serviceStateName(state: Int): String = when (state) {
        ServiceState.STATE_IN_SERVICE -> "IN_SERVICE"
        ServiceState.STATE_OUT_OF_SERVICE -> "OUT_OF_SERVICE"
        ServiceState.STATE_EMERGENCY_ONLY -> "EMERGENCY_ONLY"
        ServiceState.STATE_POWER_OFF -> "POWER_OFF"
        else -> "UNKNOWN"
    }

    /**
     * État de la carte, en clair : `READY`, `ABSENT`, `PIN_REQUIRED`…
     * C'est ce qui distingue « pas de réseau » (on peut attendre) de « pas de
     * carte » ou « carte verrouillée » (aucune attente ne servira).
     */
    private fun simStateName(state: Int): String = when (state) {
        TelephonyManager.SIM_STATE_ABSENT -> "ABSENT"
        TelephonyManager.SIM_STATE_PIN_REQUIRED -> "PIN_REQUIRED"
        TelephonyManager.SIM_STATE_PUK_REQUIRED -> "PUK_REQUIRED"
        TelephonyManager.SIM_STATE_NETWORK_LOCKED -> "NETWORK_LOCKED"
        TelephonyManager.SIM_STATE_READY -> "READY"
        TelephonyManager.SIM_STATE_NOT_READY -> "NOT_READY"
        TelephonyManager.SIM_STATE_PERM_DISABLED -> "PERM_DISABLED"
        TelephonyManager.SIM_STATE_CARD_IO_ERROR -> "CARD_IO_ERROR"
        TelephonyManager.SIM_STATE_CARD_RESTRICTED -> "CARD_RESTRICTED"
        else -> "UNKNOWN"
    }

    /**
     * Inventaire du matériel : modèle du téléphone et SIM actives.
     *
     * `carrierName` est le nom porté par la SIM elle-même (MTN, CAMTEL, Blue,
     * Orange…) : c'est la source la plus fiable pour savoir quel opérateur est
     * dans quel emplacement. `mccMnc` sert de secours (62401 MTN, 62402
     * Orange, 62403 CAMTEL). `number` est souvent vide : l'opérateur ne
     * l'expose pas toujours.
     */
    private fun describeHardware(): Map<String, Any?> {
        val sims = mutableListOf<Map<String, Any?>>()
        try {
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            for (info in sm.activeSubscriptionInfoList ?: emptyList()) {
                var mccMnc = ""
                var state = -1
                try {
                    val tm = (getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager)
                        .createForSubscriptionId(info.subscriptionId)
                    mccMnc = tm.simOperator ?: ""
                    state = tm.simState
                } catch (_: Exception) {
                }
                val number = try {
                    info.number ?: ""
                } catch (_: SecurityException) {
                    ""
                }
                sims.add(
                    mapOf(
                        "slot" to info.simSlotIndex,
                        "carrier" to (info.carrierName?.toString() ?: ""),
                        "mccMnc" to mccMnc,
                        "number" to number,
                        "subscriptionId" to info.subscriptionId,
                        "state" to state,
                    )
                )
            }
        } catch (e: Exception) {
            // Permission refusée ou service indisponible : on renvoie au moins
            // le modèle, la détection sera retentée au prochain démarrage.
        }
        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "sdk" to Build.VERSION.SDK_INT,
            "sims" to sims,
        )
    }

    /**
     * Compose le code via TelecomManager, sans avoir besoin du premier plan.
     * `false` si le service télécom refuse : l'appelant retombe alors sur
     * [callIntent] + startActivity.
     */
    private fun placeCall(code: String, slot: Int): Boolean {
        return try {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val intent = callIntent(code, slot)
            val handle = phoneAccountFor(slot)
                ?: return false
            val bundle = android.os.Bundle()
            for (key in intent.extras?.keySet() ?: emptySet()) {
                val v = intent.extras?.get(key)
                when (v) {
                    is Int -> bundle.putInt(key, v)
                    is Boolean -> bundle.putBoolean(key, v)
                    is String -> bundle.putString(key, v)
                }
            }
            bundle.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
            val uri = intent.data ?: return false
            telecom.placeCall(uri, bundle)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Appel du code USSD sur la SIM de l'emplacement [slot] (0 = SIM 1). */
    private fun callIntent(code: String, slot: Int): Intent {
        val uri = Uri.parse("tel:" + code.replace("#", Uri.encode("#")))
        val intent = Intent(Intent.ACTION_CALL, uri).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra("com.android.phone.force.slot", true)
            putExtra("Cdma_Supp", true)
            for (key in arrayOf(
                "extra_asus_dial_use_dualsim", "com.android.phone.extra.slot",
                "slot", "simslot", "sim_slot", "Subscription", "phone",
                "com.android.phone.DialingMode", "simSlot", "slot_id", "simId",
                "simnum", "phone_type", "slotId", "slotIdx"
            )) putExtra(key, slot)
        }
        phoneAccountFor(slot)?.let {
            intent.putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, it)
        }
        return intent
    }

    /** Compte téléphonique de la SIM [slot], retrouvé par son identifiant d'abonnement. */
    private fun phoneAccountFor(slot: Int): PhoneAccountHandle? {
        return try {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val accounts = telecom.callCapablePhoneAccounts
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val info = sm.getActiveSubscriptionInfoForSimSlotIndex(slot)
            val bySub = info?.let { sub ->
                accounts.firstOrNull { acc ->
                    acc.id == sub.subscriptionId.toString() ||
                        (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && sub.iccId != null && acc.id.startsWith(sub.iccId))
                }
            }
            bySub ?: if (slot in accounts.indices) accounts[slot] else null
        } catch (e: SecurityException) {
            null
        } catch (e: Exception) {
            null
        }
    }
}
