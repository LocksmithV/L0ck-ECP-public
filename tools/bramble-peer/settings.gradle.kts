// Laptop test peer: a headless Bramble node with ECP's client, driven over stdin/stdout.
rootProject.name = "bramble-peer"
include(":bramble-ecp")
project(":bramble-ecp").projectDir = file("../../app/android/bramble-ecp")

dependencyResolutionManagement {
    repositories {
        // Local Maven repo filled by app/android/bramble/build-bramble.sh
        maven {
            url = uri(providers.environmentVariable("BRAMBLE_M2")
                .orElse(System.getProperty("user.home") + "/.l0ck-ecp-toolchain/m2").get())
        }
        mavenCentral()
        google()
    }
}
