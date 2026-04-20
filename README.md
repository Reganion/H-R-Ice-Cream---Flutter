# ice_cream

A new Flutter project.

## Why does installing on a mobile device take so long?

The first install (and the first build after adding dependencies) is slow mainly because:

1. **Native code** – Plugins like **Firebase** (`firebase_core`, `firebase_database`), **Google Maps** (`google_maps_flutter`), **Google Sign-In**, and **image_picker** ship native Android (and iOS) code. Gradle has to download and compile all of that.
2. **Gradle** – The first run downloads dependencies, builds the Android app, and compiles the Flutter engine. Later builds use caches and are faster.
3. **Debug builds** – Debug mode keeps extra symbols and skips some optimizations, so builds are quicker than release but the app is larger and install can feel slow on the device.

**What helps:**

- **Second installs are much faster** – After the first successful build, use *Run* again; Gradle and Flutter caches make it noticeably quicker.
- **Use a release or profile build when you don’t need debugging:**  
  `flutter run --release` or `flutter run --profile` (then install the built APK). Release builds are optimized and install once built.
- **Keep the device connected** – USB or wireless debugging; the first transfer of a large APK can take a minute.
- Your `android/gradle.properties` already uses increased JVM memory (`-Xmx8G`), which helps Gradle run faster.
