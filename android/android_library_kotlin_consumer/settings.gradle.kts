// A Kotlin consumer on older tools (README 8.3; stage 1a 3.6): AGP 8.10, Gradle 8.13 (its own
// wrapper) and the Kotlin Gradle plugin of -Pkgp (2.2.x or 2.1.x). It compiles against the AARs
// in the Maven repository the build wrote, to show that their POMs ask for Kotlin core libraries
// these compilers can read. Run from this folder:
//   ./gradlew -Pkgp=2.1.21 -PntkVersion=<version> [-PntkRepo=<path>] :app:assembleDebug
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // android/build/m2 (scripts/build_android_library_aar.sh --m2), or dist/<version>/android/m2.
        val ntkRepo = providers.gradleProperty("ntkRepo").orElse("../build/m2").get()
        maven {
            url = uri(file(ntkRepo))
            content { includeGroup("io.github.kimjh4941") }
        }
    }
}

rootProject.name = "android_library_kotlin_consumer"
include(":app")
