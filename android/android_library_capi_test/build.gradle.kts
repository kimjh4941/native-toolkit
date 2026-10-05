import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Tests of the C ABI (C ABI design part 1, chapter 6, AC-14). Kept out of :ntk so that nothing
// test-only reaches the published AAR. GoogleTest runs in libntk_test.so, one JUnit case per
// GoogleTest case; every test runs in a process of its own (the orchestrator), because the C ABI
// initializes once per process.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.jonghyunkim.nativetoolkit.capitest"
    compileSdk = 36
    ndkVersion = "30.0.16248370"

    defaultConfig {
        minSdk = 31
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Each test in a new process, so that every initialization path starts from nothing.
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { arguments += listOf("-DANDROID_STL=c++_static") }
        }
    }

    // The initialization paths need different manifests (design 1.4).
    flavorDimensions += "startup"
    productFlavors {
        // androidx.startup as an app has it: LibraryInitializer, then NtkInitializer.
        create("startup") { dimension = "startup" }
        // Startup removed: the manual paths, and libntk.so opened by the linker only.
        create("noStartup") { dimension = "startup" }
        // NtkInitializer removed, LibraryInitializer kept.
        create("noNtkInitializer") { dimension = "startup" }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"
        }
    }
    buildFeatures { prefab = true }
    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }

dependencies {
    implementation(project(":ntk"))
    implementation(project(":android_library"))
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestUtil(libs.androidx.test.orchestrator)
    androidTestUtil(libs.androidx.test.services)
}
