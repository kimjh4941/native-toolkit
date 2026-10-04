import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.parcelize)
    alias(libs.plugins.dokka)
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
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}
