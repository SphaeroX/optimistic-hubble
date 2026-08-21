# Flutter Proguard / R8 Rules for Release Builds
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep companion app native classes
-keep class com.sphaerox.companion_app.** { *; }
-keep class com.sphaerox.companion_app.ble.** { *; }
-keep class com.sphaerox.companion_app.network.** { *; }
-keep class com.sphaerox.companion_app.service.** { *; }

# OkHttp & Coroutines
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class kotlinx.coroutines.** { *; }
