# Smart Plant — IoT Monitoring Dashboard

This repository contains a Flutter dashboard and example Arduino code for the Smart Plant IoT project.

What I changed and added:
- Added BLE scaffolding using `flutter_blue_plus` and `lib/services/bluetooth_service.dart`.
- Wired BLE into the app (`lib/main.dart`) so incoming CSV packets can replace the demo simulator.
- Improved parsing safety in `PlantData.fromRawString` and made progress values safe for `LinearProgressIndicator`.
- Added an example Arduino sketch at `hardware/arduino/plant_controller.ino` that emits CSV sensor lines and listens for pump commands.

Quick start (development):

1. Add BLE permission entries (Android/iOS):

- Android: add `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION` or new Bluetooth permissions depending on Android SDK. See `flutter_blue_plus` docs.
- iOS: add `NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription` as needed.

2. Install dependencies:

```bash
flutter pub get
```

3. Run the app:

```bash
flutter run
```

Notes & next steps before deployment:
- Calibrate sensors and implement the water-level interlock in Arduino code to avoid running the pump when the tank is empty.
- Replace the BLE auto-connect heuristic with a device selector UI.
- Add platform-specific permission handling (runtime) and background mode if required.

If you want, I can now:
- Implement a device picker UI for choosing the BLE device, or
- Replace the BLE auto-connect with a settings screen, or
- Add permission handling and Android/iOS manifest updates.
