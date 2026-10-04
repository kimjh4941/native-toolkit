import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
}

// -Pstl=c++_shared builds the consumer with the shared STL to see whether Prefab rejects the
// c++_static libntk.
val consumerStl = (findProperty("stl") as String?) ?: "c++_static"
// -PnoStartup=true removes NtkInitializer and opens libntk.so with dlopen only (dart:ffi style).
val noStartup = (findProperty("noStartup") as String?) == "true"

android {
    namespace = "com.example.ntkconsumer"
    compileSdk = 36
    ndkVersion = "30.0.16248370"

    defaultConfig {
        applicationId = "com.example.ntkconsumer"
        minSdk = 31
        targetSdk = 36
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { arguments += listOf("-DANDROID_STL=$consumerStl") }
        }
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"
        }
    }
    buildFeatures { prefab = true }
    if (noStartup) {
        sourceSets.getByName("main").manifest.srcFile("src/nostartup/AndroidManifest.xml")
        defaultConfig.externalNativeBuild.cmake.arguments += "-DNTK_DLOPEN_ONLY=ON"
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }

dependencies {
    implementation(project(":capi"))
}
