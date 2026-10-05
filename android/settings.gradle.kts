pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "native-toolkit-android"
include(":android_library")
// The C ABI. The project is named ntk because Prefab names the package after it (C ABI design 1, AC-13).
include(":ntk")
project(":ntk").projectDir = file("android_library_capi")
// Tests of the C ABI: GoogleTest in a test .so and the initialization paths (AC-14).
include(":android_library_capi_test")
include(":unity_android_plugin")
include(":app")
project(":app").projectDir = file("AndroidLibraryExample/app")
include(":testShareTarget")
project(":testShareTarget").projectDir = file("AndroidLibraryExample/testShareTarget")
include(":releaseProbe")
project(":releaseProbe").projectDir = file("AndroidLibraryExample/releaseProbe")
