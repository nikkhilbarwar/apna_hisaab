# Flutter ProGuard Rules
# Keep all models to prevent R8 from renaming fields used in JSON/Firestore mapping
-keep class com.griller.zone.models.** { *; }
-keep class **.models.** { *; }

# Keep Providers to ensure dependency injection/state management works
-keep class com.griller.zone.providers.** { *; }
-keep class **.providers.** { *; }

# Firebase & Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class id.flutter.plugins.firebase.** { *; }
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.firebase.firestore.** { *; }
-keep class com.google.firebase.storage.** { *; }
-keep class com.google.firebase.messaging.** { *; }

# WorkManager & Background Tasks
-keep class androidx.work.** { *; }
-keep class com.baseflow.googleapiavailability.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class androidx.startup.** { *; }

# Keep WorkManager initializers and Workers
-keepclassmembers class * extends androidx.work.Worker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keepclassmembers class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# SQL & Local DB
-keep class com.tekartik.sqflite.** { *; }
-keep class net.sqlcipher.** { *; }

# Prevent GSON/JSON mapping issues
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses

# Printer & Bluetooth Plugins Fix
-keep class com.anotherworld.flutter_pos_printer_platform.** { *; }
-keep class com.sersoluciones.flutter_pos_printer_platform.** { *; }
-keep class io.github.v7lin.esc_pos_utils_plus.** { *; }
-keep class android.bluetooth.** { *; }
-keep class androidx.core.app.CoreComponentFactory { *; }
-dontwarn com.sersoluciones.flutter_pos_printer_platform.**
-dontwarn com.anotherworld.flutter_pos_printer_platform.**
-dontwarn android.bluetooth.**

# Specific fix for Lateinit UninitializedPropertyAccessException during engine detach
-assumenosideeffects class com.sersoluciones.flutter_pos_printer_platform.FlutterPosPrinterPlatformPlugin {
    void onDetachedFromEngine(io.flutter.embedding.engine.plugins.FlutterPlugin$FlutterPluginBinding);
}

# Ignore missing Play Core classes
-dontwarn com.google.android.play.core.**
-dontwarn com.google.firebase.messaging.**
