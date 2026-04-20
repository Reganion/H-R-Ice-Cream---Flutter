import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.ice_cream"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.ice_cream"
        // Firebase Android libraries (e.g. firebase-database) require at least API 23.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val localProperties = Properties()
        val lp = rootProject.file("local.properties")
        if (lp.exists()) {
            lp.inputStream().use { localProperties.load(it) }
        }
        val mapsKey = localProperties.getProperty("GOOGLE_MAPS_ANDROID_KEY")
            ?: System.getenv("GOOGLE_MAPS_ANDROID_KEY")
            ?: ""
        manifestPlaceholders["GOOGLE_MAPS_ANDROID_KEY"] = mapsKey
    }

    buildTypes {
    release {
        // ADD THESE
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }

    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.11.0"))
    implementation("com.google.firebase:firebase-analytics")
}
