# Tunr: minify staat uit (isMinifyEnabled = false). Deze regels zijn voor als het later aan gaat.

# kotlinx-serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keep,includedescriptorclasses class nl.lrvdlinden.tunr.**$$serializer { *; }
-keepclassmembers class nl.lrvdlinden.tunr.** {
    *** Companion;
}
-keepclasseswithmembers class nl.lrvdlinden.tunr.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# osmdroid
-dontwarn org.osmdroid.**

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
