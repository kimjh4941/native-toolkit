buildscript {
    val kgp = (findProperty("kgp") as String?) ?: "2.2.21"
    repositories { google(); mavenCentral() }
    dependencies {
        classpath("com.android.tools.build:gradle:8.10.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kgp")
    }
}
