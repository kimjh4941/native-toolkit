import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.jonghyunkim.nativetoolkit.capi"
    compileSdk = 36
    ndkVersion = "30.0.16248370"

    defaultConfig {
        minSdk = 31
        consumerProguardFiles("consumer-rules.pro")
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            // The AAR exposes only a C API, so it declares no STL ("stl": "none" in Prefab) and
            // links libc++ statically inside libntk.so by hand (CMakeLists.txt).
            cmake { arguments += listOf("-DANDROID_STL=none") }
        }
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"
        }
    }
    buildFeatures { prefabPublishing = true }
    prefab {
        create("ntk") { headers = "src/main/cpp/include" }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }

dependencies {
    implementation("androidx.startup:startup-runtime:1.2.0")
}
