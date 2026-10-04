# androidx.startup creates the initializer by reflection from the manifest meta-data
# (Kotlin API design 8.12). Manifest components are kept by the AAPT rules.
-keep class com.jonghyunkim.nativetoolkit.common.runtime.LibraryInitializer { <init>(); }
