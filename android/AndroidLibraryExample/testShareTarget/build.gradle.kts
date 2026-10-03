// Test-only share target for the sample's UI tests (android-c-abi UI test design, U-10).
// It only displays what it received. It is not part of any distributable.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "com.jonghyunkim.android.nativetoolkit.testsharetarget"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.jonghyunkim.android.nativetoolkit.testsharetarget"
        minSdk = 31
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
}
