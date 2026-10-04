apply(plugin = "com.android.application")
apply(plugin = "org.jetbrains.kotlin.android")

configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.example.kc22"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.example.kc22"
        minSdk = 31
        targetSdk = 36
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    "implementation"("io.github.kimjh4941:android-native-toolkit:2.0.0-spike")
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}
