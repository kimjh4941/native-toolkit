import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

// The C ABI over android_library (C ABI design part 1, 5.1 and 5.4). The Gradle project is :ntk,
// so that consumers write find_package(ntk) and ntk::ntk (AC-13).
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.jonghyunkim.nativetoolkit.capi"
    compileSdk = 36
    // Pinned (AC-12). The pinned version is also what scripts/check_c_abi_contract_android.py prefers.
    ndkVersion = "30.0.16248370"

    defaultConfig {
        minSdk = 31
        consumerProguardFiles("consumer-rules.pro")
        // Consumers need compileSdk 36 or later, as for android_library.
        aarMetadata {
            minCompileSdk = 36
        }
        // 64-bit only (README D-10).
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            // The AAR exposes only a C API, so it declares no STL ("stl": "none" in Prefab) and
            // links libc++ statically inside libntk.so by hand (CMakeLists.txt, stage 1a 3.3).
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

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
        // The same consumers as android_library: Kotlin 2.1 or later (README 8.3).
        languageVersion = KotlinVersion.KOTLIN_2_2
        apiVersion = KotlinVersion.KOTLIN_2_2
    }
}

dependencies {
    implementation(project(":android_library"))
    // NtkInitializer runs at app start after android_library's LibraryInitializer (design 1.4).
    implementation(libs.androidx.startup.runtime)
}
