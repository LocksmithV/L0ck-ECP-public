allprojects {
    repositories {
        google()
        mavenCentral()
        // Bramble from Briar 1.5.24, built by bramble/build-bramble.sh
        maven {
            url = uri(providers.environmentVariable("BRAMBLE_M2")
                .orElse(System.getProperty("user.home") + "/.l0ck-ecp-toolchain/m2").get())
        }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
