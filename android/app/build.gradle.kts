import java.io.File
import java.util.Properties
import java.util.concurrent.TimeUnit

plugins {
    id("com.android.application")
    // [PRODUCTION 27/10/2026] Plugin google-services retiré : il initialisait
    // Firebase avec google-services.json (base de test `bdtestserveur`) et
    // ignorait les options de production passées dans lib/main.dart.
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.recharge237.serveur"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.recharge237.serveur"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// ─────────────────────────────────────────────────────────────────────────────
// [ACCESSIBILITE 29/10/2026] Autorisation automatique des téléphones serveurs.
//
// Android interdit à une app d'activer elle-même son service d'accessibilité,
// sauf si elle a reçu WRITE_SECURE_SETTINGS — accordable uniquement depuis un
// PC (adb), jamais depuis le téléphone. Plutôt que de lancer un script à la
// main, chaque compilation (Run d'IntelliJ, flutter build apk…) l'accorde à
// tous les téléphones branchés qui ont déjà ServeurApp. L'autorisation survit
// aux mises à jour : une seule compilation avec le téléphone branché suffit,
// ensuite l'app réactive son accessibilité seule, même loin du PC.
// Ne bloque jamais la compilation (adb absent, aucun téléphone : ignoré).
// ─────────────────────────────────────────────────────────────────────────────
val r237LocalProperties = rootProject.file("local.properties")
val r237AutoriserTelephones = tasks.register("r237AutoriserTelephones") {
    doLast {
        // [VITESSE 29/10/2026] Chaque appel adb est borné à quelques
        // secondes (processus tué au-delà) et le contrôle `dumpsys package`,
        // très lent, est supprimé : un téléphone sans fil qui répond mal ne
        // peut plus faire traîner la compilation.
        try {
            val props = Properties()
            if (r237LocalProperties.exists()) {
                r237LocalProperties.inputStream().use { flux -> props.load(flux) }
            }
            val sdk = props.getProperty("sdk.dir") ?: System.getenv("ANDROID_HOME")
            if (sdk != null) {
                val windows = System.getProperty("os.name").lowercase().contains("win")
                val adb = File(sdk, if (windows) "platform-tools/adb.exe" else "platform-tools/adb")
                if (adb.exists()) {
                    fun adbRun(secondes: Long, vararg args: String): Pair<Int, String> = try {
                        val sortie = File.createTempFile("r237adb", ".txt")
                        val p = ProcessBuilder(adb.absolutePath, *args)
                            .redirectErrorStream(true)
                            .redirectOutput(sortie)
                            .start()
                        val fini = p.waitFor(secondes, TimeUnit.SECONDS)
                        if (!fini) p.destroyForcibly()
                        val texte = sortie.readText()
                        sortie.delete()
                        Pair(if (fini) p.exitValue() else -1, texte)
                    } catch (e: Exception) {
                        Pair(-1, "")
                    }
                    val pkg = "com.recharge237.serveur"
                    val appareils = adbRun(5, "devices").second.lines().drop(1).mapNotNull { l ->
                        val c = l.trim().split(Regex("\\s+"))
                        if (c.size >= 2 && c[1] == "device") c[0] else null
                    }
                    for (d in appareils) {
                        val (code, texte) = adbRun(6, "-s", d, "shell", "pm", "grant", pkg,
                            "android.permission.WRITE_SECURE_SETTINGS")
                        val ok = code == 0 && !texte.contains("Exception")
                        logger.lifecycle("[R237] $d : réactivation automatique de " +
                            "l'accessibilité ${if (ok) "AUTORISÉE" else "non accordée (app absente ou téléphone injoignable)"}")
                    }
                }
            }
        } catch (e: Exception) {
            logger.lifecycle("[R237] autorisation des téléphones ignorée : ${e.message}")
        }
    }
}
tasks.matching { it.name == "assembleDebug" || it.name == "assembleRelease" }
    .configureEach { finalizedBy(r237AutoriserTelephones) }
