import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    println("DEBUG: key.properties trouvé, alias=${keystoreProperties["keyAlias"]}")
} else {
    println("DEBUG: key.properties INTROUVABLE à ${keystorePropertiesFile.absolutePath}")
}

android {
    namespace = "com.baroudeurs.studio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    lintOptions {
        checkReleaseBuilds = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.baroudeurs.studio"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as? String ?: System.getenv("ANDROID_KEY_ALIAS") ?: "upload"
            keyPassword = keystoreProperties["keyPassword"] as? String ?: System.getenv("ANDROID_KEY_PASSWORD") ?: "password"
            storeFile = keystoreProperties["storeFile"]?.let { file(it) } ?: file("../upload-keystore.jks")
            storePassword = keystoreProperties["storePassword"] as? String ?: System.getenv("ANDROID_STORE_PASSWORD") ?: "password"
        }
        getByName("debug") {
            // Debug signing config - no keystore required
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
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
