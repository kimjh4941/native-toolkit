buildscript {
    dependencies {
        // As android/build.gradle.kts: AGP 9 uses this KGP for its built-in Kotlin.
        classpath(libs.kotlin.gradle.plugin)
    }
}

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
}
