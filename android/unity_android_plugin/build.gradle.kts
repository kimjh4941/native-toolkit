plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.dokka)
}


version = "1.0.0"

android {
    namespace = "android.plugin"
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
    implementation(libs.androidx.appcompat.v161)
    implementation(libs.material)
    implementation(project(":android_library"))
    testImplementation(libs.junit)
    testImplementation(libs.orgjson)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}