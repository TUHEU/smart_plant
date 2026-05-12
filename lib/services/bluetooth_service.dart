import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Simple Bluetooth Classic bridge for HC-05 serial communication.
/// Connects to HC-05 device and provides serial-like data streaming.
/// Emits incoming UTF-8 sensor CSV lines on [dataStream] and allows
/// writing raw commands with [sendCommand].
class BluetoothService {
  final _controller = StreamController<String>.broadcast();

  BluetoothConnection? _connection;

  Stream<String> get dataStream => _controller.stream;

  Future<bool> scanAndConnect({Duration timeout = const Duration(seconds: 6), String nameFilter = 'HC-05'}) async {
    try {
      // stop any previous activity
      await disconnect();

      // Get bonded devices first (paired devices)
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();

      // Look for device with name containing filter
      BluetoothDevice? targetDevice;
      for (var device in bondedDevices) {
        if (device.name != null && device.name!.toLowerCase().contains(nameFilter.toLowerCase())) {
          targetDevice = device;
          break;
        }
      }

      if (targetDevice == null) {
        if (kDebugMode) print('No bonded device found with name containing: $nameFilter');
        return false;
      }

      // Attempt to connect
      _connection = await BluetoothConnection.toAddress(targetDevice.address);

      // Listen for incoming data
      _connection!.input!.listen((Uint8List data) {
        try {
          final s = utf8.decode(data).trim();
          if (s.isNotEmpty) {
            // Split by newlines in case multiple messages arrived
            final lines = s.split('\n');
            for (var line in lines) {
              if (line.trim().isNotEmpty) {
                _controller.add(line.trim());
              }
            }
          }
        } catch (e) {
          if (kDebugMode) print('Bluetooth decode error: $e');
        }
      }).onDone(() {
        if (kDebugMode) print('Bluetooth connection closed');
        disconnect();
      });

      return true;
    } catch (e) {
      if (kDebugMode) print('Bluetooth connect error: $e');
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      if (_connection != null) {
        await _connection!.close();
        _connection = null;
      }
    } catch (e) {
      if (kDebugMode) print('Disconnect error: $e');
    }
  }

  Future<bool> sendCommand(String text) async {
    if (_connection == null || !_connection!.isConnected) return false;
    try {
      final bytes = utf8.encode('$text\n'); // Add newline for Arduino
      _connection!.output.add(bytes);
      await _connection!.output.allSent;
      return true;
    } catch (e) {
      if (kDebugMode) print('Bluetooth write error: $e');
      return false;
    }
  }

  void dispose() {
    _controller.close();
    disconnect();
  }
}
