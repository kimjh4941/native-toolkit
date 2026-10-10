// The smoke of the C ABI (C ABI design part 1, chapter 6; part 2, 12.4): a C app built only from
// the Maven repository the build writes (README D-17), never from the projects of android/.
// It is a build of its own for that reason. Run it from android/ with -p:
//   ./gradlew -p android_library_capi_smoke -PntkVersion=<version> [-PntkRepo=<path>] \
//       [-Pstl=none|c++_static|c++_shared] [-PnoKeep=true] connectedAutoReleaseAndroidTest
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
    versionCatalogs {
        create("libs") { from(files("../gradle/libs.versions.toml")) }
    }
}

rootProject.name = "android_library_capi_smoke"
include(":app")
// The 32-bit library of -Pabi32 (app/build.gradle.kts).
include(":stub32")
