allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Plugins such as stellar_flutter_sdk still compile against android-34 while their AndroidX dependencies
// (credentials 1.6, core-ktx 1.15) require compileSdk 35+, which fails checkReleaseAarMetadata. Compiling a library
// against a newer SDK does not change what devices it runs on (minSdk) or opts the app into new behaviour (targetSdk).
// Registered BEFORE evaluationDependsOn so every plugin module is covered.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            (ext as? com.android.build.gradle.BaseExtension)?.let { if (project.name != "app") it.compileSdkVersion(36) }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
