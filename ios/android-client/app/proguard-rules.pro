# Plink — R8 is enabled for release builds.
# Keep rules for kotlinx.serialization, networking, and Compose.

-keepattributes *Annotation*, InnerClasses, Signature, SourceFile, LineNumberTable

# ── kotlinx.serialization ────────────────────────────────────────────────
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.plink.app.**$$serializer { *; }
-keepclassmembers class com.plink.app.** {
    *** Companion;
}
-keepclasseswithmembers class com.plink.app.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# ── Networking (OkHttp / Ktor — no-ops if absent) ───────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn io.ktor.**
-dontwarn org.slf4j.**

# ── Firebase (google-services plugin present) ───────────────────────────
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# ── Compose ──────────────────────────────────────────────────────────────
-dontwarn androidx.compose.**

# Crash reports stay readable
-renamesourcefileattribute SourceFile
