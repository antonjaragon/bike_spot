# Bike Spot

A Flutter app for your commute to Leuven station. P2 is the default parking
location; change it whenever you park elsewhere. Android and iPhone source project.

## What it does
- One current parking spot, with an editable location, level, row/zone, rack and notes.
- Optional camera/gallery photo; tap a saved photo to open it and pinch to zoom.
- “Got my bike” moves your current spot into history after confirmation.
- History details and a confirmed clear-history action.
- Offline storage inside the app, with photos copied into the saved record.
- No login, server, tracking, map API key or location permission.

## Run on your Mac
1. Install the current stable Flutter SDK: https://docs.flutter.dev/install
2. Set up Xcode for iPhone or Android Studio/Android SDK for Android using Flutter's platform setup instructions. Run `flutter doctor` and resolve platform issues.
3. Unzip this project and open Terminal in the `bike_spot` folder.
4. Run:

```sh
python3 tool/setup.py
flutter analyze
flutter test
flutter devices
flutter run
```

The setup script generates Android/iOS runners using your installed Flutter SDK,
adds iPhone photo/camera permission descriptions, sets the app name, and resolves
dependencies. It preserves existing runner folders on repeat runs. Python 3 is required.
It does not replace the app's Dart source or tests. Dependencies are resolved on your
machine; retain the resulting pubspec.lock for reproducible builds.

For a physical iPhone, open `ios/Runner.xcworkspace` in Xcode, select your signing
team and a unique bundle identifier, then use your connected phone. Camera testing
requires a physical phone. iOS signing/provisioning is required; this download is
source code, not an installable signed iPhone app.

For an Android APK after setup:

```sh
flutter build apk --release
```

The APK appears at `build/app/outputs/flutter-apk/app-release.apk`. Configure your
own release signing before distribution. iPhone release: configure signing in Xcode,
then use `flutter build ipa` and your chosen Apple distribution workflow.

## Everyday use
Before catching the train, tap **Park my bike**, enter your row/rack or take a photo,
and save. When returning, the current spot is immediately visible. Tap **Got my bike**
after collecting it. Edit keeps the original parking time. Collect before saving a
new session; only one bike is tracked at a time.

## Storage and limits
Spots and photos stay in the app's documents directory (`parking.json`); the app
makes no network requests. OS device backups may include this directory. Deleting
app data or uninstalling may remove your history. There is no cloud sync or export.
Photo selection is resized to 1600 pixels and rejects files above 8 MB. History is
kept until you clear it and can grow large with photos. Writes use a flushed temporary
file and atomic rename; failed reads block edits to protect existing data.

This is a parking notebook, not a GPS tracker or a live map of P2. Level, row and
rack are free text; no unverified parking layout or rack numbers are supplied.
On Android, if the OS closes the app during photo selection, reopen the parking
editor to recover the pending photo; unsaved text may need re-entering.

## Validation
Storage tests are included for empty state, persisted photo/details, collection,
replacement and corrupt-file protection. Flutter was not available in the creation
environment, so Flutter analysis, tests and native compilation have not been run.
Run the commands above, then test camera permission denial, photo selection,
app restart, editing and collection on your target phone before relying on it.

Plugin setup reference: https://pub.dev/packages/image_picker
