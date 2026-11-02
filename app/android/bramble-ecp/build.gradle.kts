// ECP's own Bramble client plus a small facade over a running Bramble node. Pure Java on
// bramble-api/bramble-core, shared by the Android app and the laptop test peer (tools/bramble-peer).
// Links Bramble (GPLv3); the app as a whole is AGPLv3.
plugins {
    `java-library`
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

val brambleVersion: String by project

dependencies {
    api("org.briarproject.l0ck:bramble-api:$brambleVersion")
    api("org.briarproject.l0ck:bramble-core:$brambleVersion")
    // bramble-core keeps okhttp as an implementation dep, but a Dagger component built
    // from BrambleCoreModule needs it on the compile classpath
    api("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.dagger:dagger:2.51.1")
    annotationProcessor("com.google.dagger:dagger-compiler:2.51.1")
    compileOnly("javax.annotation:jsr250-api:1.0")
}
