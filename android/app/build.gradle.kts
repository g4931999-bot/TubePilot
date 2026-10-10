import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.isFile) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}
val releaseStoreFile =
    keystoreProperties.getProperty("storeFile")
        ?.takeIf(String::isNotBlank)
        ?.let(::file)
val releaseSigningConfigured =
    listOf("keyAlias", "keyPassword", "storePassword")
        .all { !keystoreProperties.getProperty(it).isNullOrBlank() } &&
        releaseStoreFile?.isFile == true

if (!releaseSigningConfigured) {
    logger.warn(
        "Release keystore is missing or incomplete; the release APK will use the debug signing key. " +
            "Configure android/key.properties for a Play Store release."
    )
}

android {
    namespace = "com.tubepilot.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    lint {
        disable += "DeprecatedApi"
    }
    defaultConfig {
        applicationId = "com.tubepilot.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                keyAlias = requireNotNull(keystoreProperties.getProperty("keyAlias"))
                keyPassword = requireNotNull(keystoreProperties.getProperty("keyPassword"))
                storeFile = requireNotNull(releaseStoreFile)
                storePassword = requireNotNull(keystoreProperties.getProperty("storePassword"))
            }
        }
    }
    buildTypes {
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig =
                if (releaseSigningConfigured) {
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

tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
    options.compilerArgs.add("-Xlint:-deprecation")
    options.compilerArgs.add("-Xlint:-unchecked")
}

flutter {
    source = "../.."
}
