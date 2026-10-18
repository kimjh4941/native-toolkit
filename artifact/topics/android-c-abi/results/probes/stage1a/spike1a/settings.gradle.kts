// Throwaway project for the android-c-abi stage 1a spike. Not part of the repository build.
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral() }
}
rootProject.name = "spike1a"
include(":capi")
include(":consumer")
include(":capitest")
// The real library, published to a local file repository for the Kotlin 2.2 consumer probe.
include(":android_library")
// Relative to this folder in the repository (artifact/topics/android-c-abi/results/probes/stage1a/spike1a).
project(":android_library").projectDir = file("../../../../../../../android/android_library")
