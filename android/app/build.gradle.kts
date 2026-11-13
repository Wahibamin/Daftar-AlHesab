import java.util.Base64
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.X509Certificate

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.m3"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.m3"
        // You can update the following values to match your application needs.
        // Ensure minSdkVersion is at least 21 for modern plugins (sqflite, pdf, printing)
        minSdk = flutter.minSdkVersion.coerceAtLeast(21)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "com.example.m3.LicenseStorageInstrumentation"
    }

    signingConfigs {
        create("trialRelease") {
            System.getenv("TRIAL_STORE_FILE")?.let { storeFile = file(it) }
            storePassword = System.getenv("TRIAL_STORE_PASSWORD")
            keyAlias = System.getenv("TRIAL_KEY_ALIAS")
            keyPassword = System.getenv("TRIAL_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("trialRelease")
        }
    }
}

// Every Release path (including direct Flutter/Gradle) is fail-closed.
val validateTrialRelease = tasks.register("validateTrialRelease") {
    doLast {
        val defines = (project.findProperty("dart-defines") as? String).orEmpty()
            .split(',').filter { it.isNotBlank() }.associate {
                val entry = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
                entry.substringBefore('=') to entry.substringAfter('=', "")
            }
        fun decodedSize(name: String): Int = try { Base64.getDecoder().decode(defines[name].orEmpty()).size } catch (_: Exception) { 0 }
        check(defines["TRIAL_BUILD_MODE"] == "distribution" && decodedSize("TRIAL_SALT_BASE64") >= 16 &&
            decodedSize("TRIAL_VERIFIER_BASE64") == 32 &&
            (defines["TRIAL_PBKDF2_ITERATIONS"]?.toIntOrNull() ?: 0) in 120000..1000000) {
            "Trial Release requires owner configuration. Run tool/configure_trial.ps1 and tool/build_trial.ps1."
        }
        check(defines["dart.vm.product"] != "false" && defines["dart.vm.profile"] != "true") {
            "A distribution build cannot override product mode."
        }
        check(listOf("TRIAL_STORE_FILE", "TRIAL_STORE_PASSWORD", "TRIAL_KEY_ALIAS", "TRIAL_KEY_PASSWORD")
            .all { !System.getenv(it).isNullOrBlank() }) { "Owner Release signing is required; Debug signing is forbidden." }
        val path = System.getenv("TRIAL_STORE_FILE")
        check(file(path).isFile && !file(path).name.equals("debug.keystore", ignoreCase = true) &&
            !System.getenv("TRIAL_KEY_ALIAS").equals("androiddebugkey", ignoreCase = true)) { "A non-Debug owner keystore is required." }
        val keys = KeyStore.getInstance(file(path), System.getenv("TRIAL_STORE_PASSWORD").toCharArray())
        val cert = keys.getCertificate(System.getenv("TRIAL_KEY_ALIAS")) as? X509Certificate
        check(cert != null) { "Owner signing certificate not found for the selected alias." }
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString("") { "%02x".format(it) }
        check(fingerprint != "cc299511f7b81fdd01ff9a8ea4884fcbd75a0e696680f6da2c00126994018bfa" &&
            !cert.subjectX500Principal.name.contains("CN=Android Debug", ignoreCase = true)) { "Debug certificates cannot sign a Trial distribution." }
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild") dependsOn(validateTrialRelease)
}

flutter {
    source = "../.."
}
