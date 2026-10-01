import java.util.Properties
import java.io.FileInputStream

// --- 1. KEYSTORE PROPERTIES LOADER ---
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Correct package name matching your Google Play Console
    namespace = "com.mumwise.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // --- 2. RELEASE SIGNING CONFIG ---
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    compileOptions {
        // Required for flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Correct application ID for Google Play
        applicationId = "com.mumwise.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Sign with your release keystore
            signingConfig = signingConfigs.getByName("release")
            
            // Prevents the Windows strip debug error
            ndk.debugSymbolLevel = "none"

            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required for desugaring with local notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}