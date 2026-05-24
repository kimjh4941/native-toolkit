plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    id("kotlin-parcelize")
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
    namespace = "android.library"
    compileSdk = 35

    defaultConfig {
        minSdk = 31
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
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
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

tasks.dokkaHtml.configure {
    outputDirectory.set(layout.buildDirectory.dir("dokka/html"))
    dokkaSourceSets {
        // Suppress all source sets by default
        configureEach {
            suppress.set(true)
        }
        // Only document the main source set & include MODULE.md
        named("main") {
            suppress.set(false)
            includes.setFrom("MODULE.md")   // Prevent duplication: do not add in configureEach
            jdkVersion.set(11)
            skipDeprecated.set(false)
            // If necessary:
            // reportUndocumented.set(true)
            // failOnWarning.set(true)
        }
    }
}

dependencies {

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.media)
    implementation(libs.material)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}
