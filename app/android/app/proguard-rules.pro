# Bramble (from Briar's briar-android/proguard-rules.txt; bramble-android's own consumer
# rules are applied automatically). Readable stack traces beat the small size win.
-dontobfuscate
-keepattributes SourceFile, LineNumberTable, *Annotation*, Signature, InnerClasses, EnclosingMethod

# Registered as a SecureRandom provider by class name
-keep class org.briarproject.bramble.system.UnixSecureRandomSpi { *; }

# H2 database loads engines, drivers and file systems by name; R8's full mode would also
# strip the constructors Briar's narrower rules rely on
-keep class org.h2.** { *; }

-keep class javax.inject.**

-dontnote com.android.org.conscrypt.SSLParametersImpl
-dontnote org.apache.harmony.xnet.provider.jsse.SSLParametersImpl
-dontnote sun.security.ssl.SSLContextImpl
-dontwarn org.conscrypt.OpenSSLProvider
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement
