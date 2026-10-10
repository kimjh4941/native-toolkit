import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.parcelize)
    alias(libs.plugins.dokka)
    `maven-publish`
}

val cliLibraryVersion = gradle.startParameter.projectProperties["libraryVersion"]
val propertyLibraryVersion = providers.gradleProperty("libraryVersion").orNull
val libraryVersion = cliLibraryVersion ?: propertyLibraryVersion

if (libraryVersion.isNullOrBlank()) {
    logger.error("[android_library] Missing required Gradle property: libraryVersion. Pass -PlibraryVersion=<version>.")
    throw GradleException("Missing required Gradle property: libraryVersion")
}
version = libraryVersion!!
if (cliLibraryVersion != null) {
    logger.lifecycle("[android_library] libraryVersion=$libraryVersion (source=cli -P)")
} else {
    logger.lifecycle("[android_library] libraryVersion=$libraryVersion (source=gradle.properties)")
}

android {
    namespace = "com.jonghyunkim.nativetoolkit"
    compileSdk = 36

    defaultConfig {
        minSdk = 31
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
        // Consumers need compileSdk 36 or later (README 8.3). AGP 9 would otherwise write the
        // library's own compileSdk here.
        aarMetadata {
            minCompileSdk = 36
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
        // Consumers compiling with Kotlin 2.1 or later can use the library (README 8.3).
        languageVersion = KotlinVersion.KOTLIN_2_2
        apiVersion = KotlinVersion.KOTLIN_2_2
    }
    // The POM then asks for the 2.2 core libraries, not the compiler's 2.4 (stage 1a 3.6).
    coreLibrariesVersion = libs.versions.kotlinConsumer.get()
}

// The Parcelize plugin adds its own runtime at the compiler's version, which needs stdlib 2.4.
configurations.configureEach {
    resolutionStrategy.force(libs.kotlin.parcelize.runtime)
}

dokka {
    dokkaPublications.html {
        outputDirectory.set(layout.buildDirectory.dir("dokka/html"))
    }
    // Dokka v2 names the Android source sets after the variants (debug, release, debugUnitTest, ...)
    // and registers them late. Document only the published variant and include MODULE.md there
    // (adding it to every source set duplicates it).
    dokkaSourceSets.configureEach {
        val isPublished = name == "release"
        suppress.set(!isPublished)
        if (isPublished) {
            includes.from("MODULE.md")
            jdkVersion.set(17)
            skipDeprecated.set(false)
        }
    }
}

dependencies {

    implementation(libs.androidx.core.ktx)
    // AndroidDialogFragment exposes DialogFragment in the public API.
    api(libs.androidx.fragment)
    implementation(libs.androidx.media)
    // LibraryInitializer (public, extends androidx.startup.Initializer) registers the foreground
    // tracker at app start (Kotlin API design 8.1).
    api(libs.androidx.startup.runtime)
    // The suspend versions of the manager APIs (Kotlin API design 8.7, 8.8).
    implementation(libs.kotlinx.coroutines.core)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.uiautomator)
}

// The Maven publication (README D-17): io.github.kimjh4941:android-native-toolkit. The build script publishes it to
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
                artifactId = "android-native-toolkit"
                version = project.version.toString()
                from(component)
                // The resolved versions (after the Kotlin pins above) go into the POM.
                versionMapping {
                    usage("java-api") { fromResolutionOf("releaseCompileClasspath") }
                    usage("java-runtime") { fromResolutionOf("releaseRuntimeClasspath") }
                }
                pom {
                    name.set("Native Toolkit for Android")
                    description.set("The Kotlin API of Native Toolkit: clipboard, dialogs, notifications and share.")
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
