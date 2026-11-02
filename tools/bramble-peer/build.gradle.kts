plugins {
    application
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

val brambleVersion: String by project

dependencies {
    implementation(project(":bramble-ecp"))
    implementation("org.briarproject.l0ck:bramble-java:$brambleVersion")
    implementation("com.google.dagger:dagger:2.51.1")
    annotationProcessor("com.google.dagger:dagger-compiler:2.51.1")
    compileOnly("javax.annotation:jsr250-api:1.0")
    // Tor and the lyrebird bridge client as classpath resources, unpacked by the Tor plugin
    runtimeOnly("org.briarproject:tor-linux:0.4.9.15")
    runtimeOnly("org.briarproject:lyrebird-linux:0.6.2")
}

application {
    mainClass.set("cz.l0ck.ecp.peer.Main")
}
