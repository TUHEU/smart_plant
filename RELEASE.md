Release checklist

- Android
  - Generate release keystore and set `storeFile`/`storePassword`/`keyAlias`/`keyPassword` in `android/app/build.gradle` or CI secrets.
  - Run `flutter build apk --release` and verify on device.
  - Test on API 21+ devices.
  - Prepare Play Store listing and follow target SDK requirements.

- iOS
  - Configure signing in Xcode (App Store Connect) and set proper entitlements.
  - Ensure `NSBluetoothAlwaysUsageDescription` and related keys are present in `ios/Runner/Info.plist`.
  - Run `flutter build ipa` with CI credentials or via Xcode.

- Background & Permissions
  - For long-running BLE background work, implement platform-specific services (not covered here).
  - Document required runtime permissions for Android 12+ (bluetoothScan, bluetoothConnect) and provide in-app rationale.

- QA
  - Test with target BLE peripheral (ESP32/HM-10) and with USB-serial Arduino.
  - Validate calibration round-trip (app sends `CAL,min,max`, device responds `CAL_ACK,min,max`).

- CI
  - Add signed artifact publishing steps to CI and protect keystore secrets.

- Post-release
  - Monitor analytics and crash reports.

