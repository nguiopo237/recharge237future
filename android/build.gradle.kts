allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Fix for old plugins (e.g. sms_advanced, telephony, ussd_flutter, ussd_launcher)
// that don't declare a namespace, or declare mismatched Java/Kotlin JVM targets,
// which recent versions of the Android Gradle Plugin / Kotlin Gradle Plugin reject.
// Must be registered before evaluationDependsOn(":app") below, which
// forces early evaluation of subprojects via the Flutter Gradle plugin.
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android")
        if (androidExtension is com.android.build.gradle.BaseExtension) {
            if (androidExtension.namespace == null) {
                androidExtension.namespace = group.toString()
            }
            // Old plugins pin their own (often mismatched) Java/Kotlin targets;
            // force both to the same value the app itself uses (17).
            androidExtension.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
            androidExtension.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            // Old plugins also pin an outdated compileSdkVersion that is too low
            // for their own transitive androidx dependencies; bump it up.
            val currentCompileSdk = androidExtension.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (currentCompileSdk < 36) {
                androidExtension.compileSdkVersion("android-36")
            }
        }

        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
