import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties (android/key.properties)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.pathseeker.international"

    // ✅ Plugins require NDK 27.x
    ndkVersion = "27.0.12077973"

    // ✅ Your setup
    compileSdk = 36

    defaultConfig {
        applicationId = "com.pathseeker.international"
        minSdk = 24
        targetSdk = 36

        versionCode = 31
        versionName = "1.0.19"

        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                val storeFilePath = keystoreProperties["storeFile"]?.toString()?.trim()
                if (!storeFilePath.isNullOrEmpty()) {
                    storeFile = file(storeFilePath)
                } else {
                    throw GradleException("storeFile missing in key.properties for release signing.")
                }

                val storePasswordVal = keystoreProperties["storePassword"]?.toString()
                val keyAliasVal = keystoreProperties["keyAlias"]?.toString()
                val keyPasswordVal = keystoreProperties["keyPassword"]?.toString()

                if (storePasswordVal.isNullOrEmpty() || keyAliasVal.isNullOrEmpty() || keyPasswordVal.isNullOrEmpty()) {
                    throw GradleException("key.properties must contain storePassword, keyPassword, and keyAlias.")
                }

                storePassword = storePasswordVal
                keyAlias = keyAliasVal
                keyPassword = keyPasswordVal
            } else {
                throw GradleException("key.properties not found — please create android/key.properties with release signing info.")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt"
            )
        }
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

dependencies {
    // Multidex
    implementation("androidx.multidex:multidex:2.0.1")

    // Desugaring support
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")
}
