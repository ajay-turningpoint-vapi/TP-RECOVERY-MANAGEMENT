# Flutter's own embedding — required, R8 otherwise strips classes the
# engine looks up via reflection at runtime.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# flutter_local_notifications uses reflection for its scheduled-notification
# receivers/services; stripping them silently breaks notification delivery
# on some OEM ROMs.
-keep class com.dexterous.** { *; }

# gson (a transitive dependency of flutter_local_notifications) — keep
# generic signatures so its (de)serialization keeps working under R8.
-keepattributes Signature
-keepattributes *Annotation*
