# JNI looks up everything in the capi.jni package by name, and RegisterNatives binds its native
# methods by name (C ABI design part 1, AC-20).
-keep class com.jonghyunkim.nativetoolkit.capi.jni.** { *; }
# androidx.startup creates the initializer by reflection.
-keep class com.jonghyunkim.nativetoolkit.capi.NtkInitializer { <init>(); }
