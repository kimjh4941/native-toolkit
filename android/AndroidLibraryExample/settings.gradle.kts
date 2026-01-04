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

rootProject.name = "AndroidLibraryExample"
include(":app")
include(":android_library")
project(":android_library").projectDir =
    File("/Users/jonghyunkim/Desktop/native-toolkit/android/android_library")
include(":unity_android_plugin")
project(":unity_android_plugin").projectDir =
    File("/Users/jonghyunkim/Desktop/native-toolkit/android/unity_android_plugin")
