# Room instantiates generated database implementations reflectively.
# WorkManager 2.7.0 / Room 2.2.5 consumer rules keep the class but R8 can remove
# its implicit no-argument constructor in optimized release builds.
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}

# ML Kit pose detection: R8 strips or renames what the plugins reach through
# the method channel and ML Kit loads reflectively, and every camera frame
# then fails in InputImage.fromByteArray ("Getting Image failed") in release.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google.android.odml.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_pose_detection.** { *; }
-dontwarn com.google.mlkit.**
