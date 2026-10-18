buildscript {
    dependencies { classpath(libs.kotlin.gradle.plugin) }
}
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.parcelize) apply false
    alias(libs.plugins.dokka) apply false
}

// Publishes android_library with a POM so that a consumer sees its dependencies (D-17).
project(":android_library") {
    apply(plugin = "maven-publish")
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension> {
            publishing { singleVariant("release") }
        }
    }
    // Probe: depend on the 2.2 core libraries so that Kotlin 2.1/2.2 consumers can compile.
    if ((findProperty("core22") as String?) == "true") {
        plugins.withId("com.android.library") {
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinProjectExtension> {
                coreLibrariesVersion = "2.2.21"
            }
        }
        // The Parcelize plugin adds its own runtime (2.4.20, which needs stdlib 2.4.20).
        configurations.configureEach {
            resolutionStrategy.force("org.jetbrains.kotlin:kotlin-parcelize-runtime:2.2.21")
        }
    }
    // AGP creates the "release" component late, so create the publication when it appears.
    components.matching { it.name == "release" }.all {
        val component = this
        extensions.configure<PublishingExtension> {
            publications {
                create<MavenPublication>("release") {
                    groupId = "io.github.kimjh4941"
                    artifactId = "android-native-toolkit"
                    version = "2.0.0-spike"
                    from(component)
                    // Write the resolved versions (after the force above) into the POM.
                    versionMapping {
                        usage("java-api") { fromResolutionOf("releaseCompileClasspath") }
                        usage("java-runtime") { fromResolutionOf("releaseRuntimeClasspath") }
                    }
                }
            }
            repositories { maven { url = uri("${rootDir}/m2") } }
        }
    }
}
