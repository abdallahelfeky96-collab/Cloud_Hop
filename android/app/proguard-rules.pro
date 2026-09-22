# Cloud Hop — app-specific R8 / ProGuard rules.
# Merged with proguard-android-optimize.txt via android/app/build.gradle.kts.
#
# Root cause of the reported crash:
#   java.lang.RuntimeException: Unable to get provider
#   androidx.startup.InitializationProvider:
#   java.lang.RuntimeException: Failed to create an instance of
#   androidx.work.impl.WorkDatabase
# R8 stripped / obfuscated the Room-generated WorkDatabase implementation
# that WorkManager creates reflectively at startup. The rules below keep
# those classes, their members, and the annotations Room needs.

# Room uses generics signatures + annotations to generate/read the DB impl.
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes *Annotation*

# --- androidx.startup (triggers WorkManager auto-init) ---
-keep class androidx.startup.** { *; }
-keep class * extends androidx.startup.Initializer { *; }

# --- WorkManager ---
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context,androidx.work.WorkerParameters);
}
# Internal Room database WorkManager instantiates via reflection.
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.model.** { *; }
-dontwarn androidx.work.**

# --- Room ---
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-keep class * implements androidx.room.migration.Migration { *; }
-keepclassmembers class * {
    @androidx.room.Dao <methods>;
    @androidx.room.Query <methods>;
    @androidx.room.Insert <methods>;
    @androidx.room.Update <methods>;
    @androidx.room.Delete <methods>;
    @androidx.room.Transaction <methods>;
}
-dontwarn androidx.room.**

# ListenableFuture (Guava) types referenced by WorkManager signatures.
-dontwarn com.google.common.util.concurrent.**
