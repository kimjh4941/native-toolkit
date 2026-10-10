buildscript {
    val kgp = providers.gradleProperty("kgp").orNull ?: throw GradleException("Pass -Pkgp=<Kotlin Gradle plugin version>")
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.10.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kgp")
    }
}
