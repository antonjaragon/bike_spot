# Leuven Conmute — parking + trains

## Updating your existing app
Copy `lib/`, `assets/`, `test/`, `tool/setup.py`, and `pubspec.yaml` from this
project into your existing bike_spot project. Keep your existing android/ and ios/
folders, signing settings, and application identifier. This keeps the installed
app's parking data when you update it. The existing store.dart format is unchanged.

In the project folder run:

```sh
python3 tool/setup.py
flutter analyze
flutter test
flutter run
```

Setup downloads dependencies, adds Android INTERNET permission to the main
manifest, preserves iOS camera permission descriptions, and generates Android/iOS
launcher icons from assets/app_icon.png. Stop and rebuild the app; hot reload does
not change launcher icons. Launchers may take a little time to refresh their cache.

For a new checkout, the same script generates the Android/iOS platform folders
first. Requires Python 3 and current stable Flutter on PATH. See
https://docs.flutter.dev/install for Flutter and platform toolchain installation.
For iPhone, configure Xcode signing and run on a physical phone to test the camera.

## Two screens and following a journey
The app always starts on Bike. Swipe left to Trains, or tap the bottom tabs.
Swipe right to return. Parking drafts and the selected train survive page changes.
The app's visible name is **Leuven Conmute**; the internal package/application IDs
stay unchanged so updating the app preserves saved parking data.

Train cards show scheduled times, expected times for delayed services, reported
delay minutes, cancellations, transfer details and platform changes. Delays,
changed platforms, cancellations and service alerts use a soft red background.
Missing delay data is labelled unavailable rather than interpreted as on-time.

Tap **Follow this journey** to pin one connection. The app continues querying that
connection's original route/date/time, including after departure. It matches the
journey by its scheduled first/last service and time. The noon direction switch is
paused while following. Tap **Stop following** to return to upcoming trains in the
current time-based direction. Following is in memory for this session; a full app
restart starts on Bike and resets the followed trip. It does not track your GPS.

If iRail stops returning the followed connection, its last known details are
explicitly labelled with a warning, rather than silently selecting another train.
If the journey is rescheduled enough to change its identity, this warning also
appears. Following is a periodically updated journey view, not a live train map.
The last update time and age remain visible. This is iRail data, not a direct feed
from the NMBS app, and updates may differ or arrive later.

## Behavior
- Before 12:00 in Europe/Brussels: Gent-Dampoort → Leuven.
- At/after 12:00: Leuven → Gent-Dampoort. Resets to outbound at midnight.
- Uses Belgian timezone data, including daylight saving, regardless of phone timezone.
- Loads up to six connections from now and shows the nearest four upcoming ones.
- Times are scheduled Belgian times with reported delays alongside them.
- Tap a journey for expected times, services, transfer stations/platforms and alerts.
- Cancelled connections remain clearly marked; already-departed trains are hidden.
- Checks direction every 15 seconds while foregrounded and upon resume. Timetables
  refresh no more than once per minute, respecting longer server cache/retry periods.
- Refresh button is disabled during requests and cooldowns. No background polling.
- Internet errors show an error; followed journeys retain clearly marked last known details.
- Parking stays simple: P1/P2/P3, optional section/column number, optional photo, Save.
  P2 remains the initial default. Changing parking area clears draft section/photo.

## Timetable source
NMBS/SNCB connections are retrieved via the independent iRail API, not an official
NMBS app or authenticated NMBS API. No API key is needed. Requests send the two
station names and departure time; your parking section and photo are never sent.
Data can be delayed or incomplete; consult station displays for last-minute changes.
The API uses nl station names; disruption text may be Dutch.

Documentation: https://docs.irail.be/
Status: https://status.irail.be/
The service sees your IP and the BikeSpot User-Agent. For public distribution,
add your contact URL/email to the User-Agent in lib/trains.dart, following iRail's
best practices. Do not increase polling aggressively.

## Icon
assets/app_icon.png is the bike-and-train launcher artwork, made with the built-in
image generation tool. Prompt: minimal bold cream bicycle in front of a simple train
symbol, forest-green background, lime accent, no text or company logos, central
composition suitable for mobile icon masks. Launcher generation uses
https://pub.dev/packages/flutter_launcher_icons.

## Validation and limits
Flutter/Dart were not installed in the creation environment. Flutter analysis,
unit tests and native builds could not be run here. A live iRail request succeeded with six Gent-Dampoort → Leuven connections;
the response fields were checked against the parser. End-to-end display on a phone
has not been verified.
Included tests cover summer/winter noon boundaries, midnight, DST, delay parsing,
transfer cancellations and invalid responses, plus the existing parking storage tests.
The setup script passed Python syntax checking; icon/configuration/source files
were checked for consistency. Verify live departures, offline behavior, noon/resume,
camera, saved parking and the new launcher icon on your phone.

Supports the existing Android/iPhone project; this update does not add web or desktop
runners. Parking has no cloud sync. Uninstalling or clearing app data can erase it.
Do not uninstall simply to update the launcher icon.

Version 1.2 changes were structurally checked, but Flutter analysis and device tests still need to run locally.
