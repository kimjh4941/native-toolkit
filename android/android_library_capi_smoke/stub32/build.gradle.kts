// A 32-bit library of the app's own (-Pabi32 in app/build.gradle.kts). No Prefab here: AGP checks
// a Prefab package for every ABI the CMake build has, and the C ABI has no armeabi-v7a.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.jonghyunkim.nativetoolkit.smoke.stub32"
    compileSdk = 36
    ndkVersion = "30.0.16248370"
    defaultConfig {
        minSdk = 31
        ndk { abiFilters += listOf("armeabi-v7a") }
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"
        }
    }
}
