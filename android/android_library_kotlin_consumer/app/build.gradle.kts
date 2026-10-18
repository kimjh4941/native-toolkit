apply(plugin = "com.android.application")
apply(plugin = "org.jetbrains.kotlin.android")

val ntkVersion = providers.gradleProperty("ntkVersion").orNull
    ?: throw GradleException("Pass -PntkVersion=<the version in the Maven repository>")

configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.jonghyunkim.nativetoolkit.kotlinconsumer"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.jonghyunkim.nativetoolkit.kotlinconsumer"
        minSdk = 31
        targetSdk = 36
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}

dependencies {
    "implementation"("io.github.kimjh4941:android-native-toolkit:$ntkVersion")
    "implementation"("io.github.kimjh4941:android-native-toolkit-capi:$ntkVersion")
}
