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
include(":unity_android_plugin")
include(":app")
project(":app").projectDir = file("AndroidLibraryExample/app")
include(":testShareTarget")
project(":testShareTarget").projectDir = file("AndroidLibraryExample/testShareTarget")
