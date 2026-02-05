pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // ✅ Flutter engine local maven (REQUIRED for io.flutter:* debug artifacts)
        maven { url = uri("$flutterSdkPath/bin/cache/artifacts/engine/android") }

        google()
        mavenCentral()
        gradlePluginPortal()

        // ✅ Juspay HyperSDK Maven (keep)
        maven { url = uri("https://maven.juspay.in/jp-build-packages/hyper-sdk/") }
    }
}

dependencyResolutionManagement {
    
    repositories {
        // ✅ Flutter engine local maven (REQUIRED for io.flutter:* debug artifacts)
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }

        maven { url = uri("$flutterSdkPath/bin/cache/artifacts/engine/android") }

        google()
        mavenCentral()

        // ✅ Juspay HyperSDK Maven
        maven { url = uri("https://maven.juspay.in/jp-build-packages/hyper-sdk/") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
