// Muss ganz oben stehen und importiert sein: im Gradle-Kotlin-DSL ist `java`
// bereits die Java-Extension des Projekts, `java.util.Properties()` löst
// deshalb nicht auf.
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signatur-Zugang für den Play-Upload. Liegt in android/key.properties
// (gitignored, siehe android/.gitignore) und fehlt auf frischen Checkouts —
// dann fällt der Release-Build bewusst auf den Debug-Key zurück, damit
// `flutter run --release` weiter funktioniert. Ein Play-Upload braucht die
// Datei; ohne sie lehnt die Console das AAB als debug-signiert ab.
val keystoreProperties =
    Properties().apply {
        val keystorePropertiesFile = rootProject.file("key.properties")
        if (keystorePropertiesFile.exists()) {
            keystorePropertiesFile.inputStream().use { load(it) }
        }
    }
val hasUploadKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "app.matchup.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Muss zum Deep-Link-Schema in AppConfig/AndroidManifest passen.
        applicationId = "app.matchup.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Kommen aus pubspec.yaml (version: x.y.z+build). Vor jedem Upload
        // muss die Build-Nummer hinter dem + steigen, Play nimmt denselben
        // versionCode kein zweites Mal an.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasUploadKey) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
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
