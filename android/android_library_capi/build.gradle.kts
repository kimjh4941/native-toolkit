import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

// The C ABI over android_library (C ABI design part 1, 5.1 and 5.4). The Gradle project is :ntk,
// so that consumers write find_package(ntk) and ntk::ntk (AC-13).
plugins {
    alias(libs.plugins.android.library)
    `maven-publish`
}

// The same version as android_library (-PlibraryVersion, or gradle.properties).
version = providers.gradleProperty("libraryVersion").get()

// Test only: -Pntk.hwasan=true builds libntk.so for arm64 with HWASan (C ABI design part 1,
// chapter 6). HWASan does not support a static libc++, so this build uses c++_shared and is not
// the shipped link form; never publish it.
val hwasan = providers.gradleProperty("ntk.hwasan").orNull == "true"

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
        ndk { abiFilters += if (hwasan) listOf("arm64-v8a") else listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            // The AAR exposes only a C API, so it declares no STL ("stl": "none" in Prefab) and
            // links libc++ statically inside libntk.so by hand (CMakeLists.txt, stage 1a 3.3).
            cmake {
                arguments += if (hwasan) {
                    listOf("-DANDROID_STL=c++_shared", "-DANDROID_SANITIZE=hwaddress", "-DNTK_HWASAN=ON")
                } else {
                    listOf("-DANDROID_STL=none")
                }
            }
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
    testOptions {
        // android.util.Log in the code under test returns defaults on the JVM.
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
        // The same consumers as android_library: Kotlin 2.1 or later (README 8.3).
        languageVersion = KotlinVersion.KOTLIN_2_2
        apiVersion = KotlinVersion.KOTLIN_2_2
    }
    // The POM then asks for the 2.2 core libraries, not the compiler's 2.4 (stage 1a 3.6).
    coreLibrariesVersion = libs.versions.kotlinConsumer.get()
}

dependencies {
    implementation(project(":android_library"))
    // NtkInitializer runs at app start after android_library's LibraryInitializer (design 1.4).
    implementation(libs.androidx.startup.runtime)
    testImplementation(libs.junit)
}

// The Maven publication (README D-17): io.github.kimjh4941:android-native-toolkit-capi. The build script publishes it to
// android/build/m2 and copies that to dist/<version>/android/m2/.
android {
    publishing { singleVariant("release") }
}

// AGP creates the "release" component late, so the publication is created when it appears.
components.matching { it.name == "release" }.all {
    val component = this
    publishing {
        publications {
            create<MavenPublication>("release") {
                groupId = "io.github.kimjh4941"
                artifactId = "android-native-toolkit-capi"
                version = project.version.toString()
                from(component)
                // The resolved versions (after the Kotlin pins above) go into the POM.
                versionMapping {
                    usage("java-api") { fromResolutionOf("releaseCompileClasspath") }
                    usage("java-runtime") { fromResolutionOf("releaseRuntimeClasspath") }
                }
                pom {
                    name.set("Native Toolkit for Android, C ABI")
                    description.set("The C ABI of Native Toolkit (libntk.so with Prefab headers) over android-native-toolkit.")
                    url.set("https://github.com/kimjh4941/native-toolkit")
                    licenses {
                        license {
                            name.set("Apache License, Version 2.0")
                            url.set("https://www.apache.org/licenses/LICENSE-2.0")
                        }
                    }
                }
            }
        }
        repositories { maven { url = uri(rootProject.layout.buildDirectory.dir("m2")) } }
    }
}
