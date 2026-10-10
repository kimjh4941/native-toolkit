import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// The smoke app (settings.gradle.kts). Options:
//   -PntkVersion=<version>  the version of io.github.kimjh4941:android-native-toolkit-capi (required)
//   -Pstl=<stl>             the app's own STL: none (C only), c++_static or c++_shared (stage 1a 3.3)
//   -PnoKeep=true           drops the capi AAR's keep rules, to see that R8 then breaks the
//                           initialization without crashing the app (part 1, chapter 6)
//   -Pabi32=true            adds armeabi-v7a with a stub library of the app's own (:stub32), as an
//                           app with 32-bit code has: installed as 32-bit, libntk.so (64-bit only)
//                           is missing and the app has to keep running (README chapter 9). The app's
//                           own CMake stays 64-bit: AGP rejects a Prefab package that lacks an ABI
//                           the CMake build has (CXX1210)
// The "auto" flavor initializes through androidx.startup; "manual" removes Startup and calls
// ntk_android_init (part 1, 1.4; AC-20). The instrumented test runs against the R8 release build.
plugins {
    alias(libs.plugins.android.application)
}

val ntkVersion = providers.gradleProperty("ntkVersion").orNull
    ?: throw GradleException("Pass -PntkVersion=<the version in the Maven repository>")
val appStl = providers.gradleProperty("stl").orElse("none").get()
require(appStl in listOf("none", "c++_static", "c++_shared")) { "-Pstl must be none, c++_static or c++_shared" }
val noKeep = providers.gradleProperty("noKeep").orNull == "true"
val abi32 = providers.gradleProperty("abi32").orNull == "true"

android {
    namespace = "com.jonghyunkim.nativetoolkit.smoke"
    compileSdk = 36
    ndkVersion = "30.0.16248370"

    defaultConfig {
        applicationId = "com.jonghyunkim.nativetoolkit.smoke"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = ntkVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        testProguardFiles("test-proguard-rules.pro")
        // What the APK carries; the app's own CMake builds the 64-bit ABIs only.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") + if (abi32) listOf("armeabi-v7a") else emptyList() }
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=$appStl")
                abiFilters("arm64-v8a", "x86_64")
            }
        }
        buildConfigField("String", "STL", "\"$appStl\"")
        buildConfigField("boolean", "NO_KEEP", "$noKeep")
    }

    flavorDimensions += "init"
    productFlavors {
        create("auto") {
            dimension = "init"
            buildConfigField("boolean", "MANUAL", "false")
        }
        create("manual") {
            dimension = "init"
            buildConfigField("boolean", "MANUAL", "true")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
            if (noKeep) {
                optimization { keepRules { ignoreFrom("io.github.kimjh4941:android-native-toolkit-capi") } }
            }
        }
    }
    testBuildType = "release"

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"
        }
    }
    buildFeatures {
        prefab = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }

dependencies {
    implementation("io.github.kimjh4941:android-native-toolkit-capi:$ntkVersion")
    // The Kotlin API too, as a host that uses it next to the C ABI declares it (README section 3):
    // the capi POM depends on it for run time only.
    implementation("io.github.kimjh4941:android-native-toolkit:$ntkVersion")
    if (abi32) implementation(project(":stub32"))
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.uiautomator)
}
