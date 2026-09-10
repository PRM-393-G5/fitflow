# Room instantiates generated database implementations reflectively.
# WorkManager 2.7.0 / Room 2.2.5 consumer rules keep the class but R8 can remove
# its implicit no-argument constructor in optimized release builds.
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}
