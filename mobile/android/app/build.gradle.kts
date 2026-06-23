plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // KSP — required by the dtn-mesh engine's Room database (annotation processing).
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.example.nest_link"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.nest_link"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // dtn-mesh engine requires API 26+ (startForegroundService, etc.).
        minSdk = maxOf(26, flutter.minSdkVersion)
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

// ── dtn-mesh engine dependencies ──────────────────────────────────────────
// NOTE: roomVersion / KSP plugin version are the most likely values to need a
// bump on first Gradle sync (Kotlin 2.3.20 / AGP 9 toolchain). See docs/SPRINT-1.md.
val roomVersion = "2.7.2"

dependencies {
    // Room (mesh persistence) — classic API, KSP2 processor
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    ksp("androidx.room:room-compiler:$roomVersion")

    // Foreground LifecycleService used by DTNService
    implementation("androidx.lifecycle:lifecycle-service:2.8.7")
    implementation("androidx.core:core-ktx:1.13.1")

    // Bundle (de)serialization
    implementation("com.google.code.gson:gson:2.11.0")

    // Coroutines (DTNService, transports)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // USB serial for optional LoRa OTG module (engine references these symbols)
    implementation(files("libs/usb-serial-for-android-3.4.6.aar"))
}
