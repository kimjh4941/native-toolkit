// Test-only app for the release checks of android_library (Kotlin API design 0.8 and 12: IT-19,
// IT-22, IT-26). It consumes the library as an app does, built with R8, and checks itself when
// scripts/test_android.sh starts it with a case. It is not part of any distributable.
plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "com.jonghyunkim.android.nativetoolkit.releaseprobe"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.jonghyunkim.android.nativetoolkit.releaseprobe"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    flavorDimensions += "probe"
    productFlavors {
        // IT-22, and the earlier version of IT-26.
        create("full") {
            dimension = "probe"
        }
        // The later version of IT-26: same app, a new version code and other obfuscated names.
        create("fullNext") {
            dimension = "probe"
            versionCode = 2
            versionName = "2.0.0"
            proguardFile("proguard-next.pro")
        }
        // IT-19: the permissions of design 8.12 removed (src/noPermissions/AndroidManifest.xml).
        create("noPermissions") {
            dimension = "probe"
            applicationIdSuffix = ".nopermissions"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Installed by the test script only; the debug key keeps the versions updatable.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":android_library"))
}
