// A consumer on the lower tool versions (README 8.3): AGP 8.10.0, Gradle 8.13, Kotlin from -Pkgp.
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositories {
        google(); mavenCentral()
        // Written by spike1a (:android_library:publishReleasePublicationToMavenRepository).
        maven { url = file("../spike1a/m2").toURI() }
    }
}
rootProject.name = "kc22"
include(":app")
