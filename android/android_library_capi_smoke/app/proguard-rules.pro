# The smoke app's own classes: JNI binds Smoke's native methods by name, and the instrumented test
# calls them. The library's classes are kept by its AAR's consumer rules (or not, with -PnoKeep).
-keep class com.jonghyunkim.nativetoolkit.smoke.** { *; }

# The instrumented test runs in the app's process with the app's copy of the classes they share:
# keep what androidx.test needs and the app does not use (androidx.tracing, parts of the Kotlin
# standard library). None of it is the C ABI's, whose shrinking is what the smoke checks.
-keep class androidx.tracing.** { *; }
-keep class kotlin.** { *; }
