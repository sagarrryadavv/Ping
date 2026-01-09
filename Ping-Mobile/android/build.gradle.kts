// File: android/build.gradle.kts (Top-Level)

// Defines properties used across multiple modules, like versions
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Essential Android Gradle Plugin (AGP) version
        classpath("com.android.tools.build:gradle:8.1.4")
        
        // Essential Kotlin Gradle Plugin version
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22")
        
        // CRITICAL: Google Services Plugin for Firebase configuration
        classpath("com.google.gms:google-services:4.4.0")
    }
}

// Your existing custom build directory logic (corrected to be placed after buildscript)
// This logic may still cause issues, but we keep it minimal for now.
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}