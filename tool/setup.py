#!/usr/bin/env python3
"""Generate native runners using the installed Flutter SDK, then set permissions."""
import pathlib
import plistlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
if not shutil.which('flutter'):
    raise SystemExit('Install Flutter and put flutter on PATH first: https://docs.flutter.dev/install')
if not (root / 'android').exists() or not (root / 'ios').exists():
    with tempfile.TemporaryDirectory(prefix='bike_spot_') as tmp:
        generated = pathlib.Path(tmp) / 'bike_spot'
        subprocess.run(['flutter', 'create', '--platforms=android,ios', '--org=com.bikespot',
                        '--project-name=bike_spot', str(generated)], check=True)
        for name in ['android', 'ios']:
            if not (root / name).exists():
                shutil.copytree(generated / name, root / name)
        if not (root / '.metadata').exists():
            shutil.copy2(generated / '.metadata', root / '.metadata')
info = root / 'ios/Runner/Info.plist'
with info.open('rb') as f:
    data = plistlib.load(f)
data.update(CFBundleDisplayName='Bike Spot',
            NSCameraUsageDescription='Take a photo to remember where you parked your bike.',
            NSPhotoLibraryUsageDescription='Choose a photo of your bike parking spot.')
with info.open('wb') as f:
    plistlib.dump(data, f, sort_keys=False)
manifest = root / 'android/app/src/main/AndroidManifest.xml'
manifest.write_text(manifest.read_text().replace('android:label="bike_spot"', 'android:label="Bike Spot"'))
subprocess.run(['flutter', 'pub', 'get'], cwd=root, check=True)
print('Ready. Run flutter analyze, flutter test, then flutter run.')
