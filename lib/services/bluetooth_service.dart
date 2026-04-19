import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Simple BLE bridge that scans for a device and subscribes to the first
/// notify characteristic it finds. Emits incoming UTF-8 sensor CSV lines
/// on [dataStream] and allows writing raw commands with [sendCommand].
class BleService {
  final _controller = StreamController<String>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  bool _connected = false;
  bool _autoReconnect = false;
  Timer? _reconnectTimer;
  // using static API from flutter_blue_plus where appropriate

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar; // device -> app (notify)
  BluetoothCharacteristic? _txChar; // app -> device (write)

  Stream<String> get dataStream => _controller.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  Future<bool> scanAndConnect({
    Duration timeout = const Duration(seconds: 6),
    String nameFilter = 'Arduino',
  }) async {
    try {
      // stop any previous activity
      await disconnect();

      final results = <ScanResult>[];
      // start scanning and collect results
      FlutterBluePlus.startScan(timeout: timeout);
      final sub = FlutterBluePlus.scanResults.listen((r) {
        results.clear();
        results.addAll(r);
      });

      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();
      await sub.cancel();

      // pick first device with name containing filter or first available
      ScanResult? pick;
      for (var r in results) {
        if (r.device.name.isNotEmpty &&
            r.device.name.toLowerCase().contains(nameFilter.toLowerCase())) {
          pick = r;
          break;
        }
      }
      pick ??= results.isNotEmpty ? results.first : null;
      if (pick == null) return false;

      _device = pick.device;
      // connect to the chosen device
      await _device!.connect();

      final services = await _device!.discoverServices();
      // find a characteristic that supports notify/read for incoming data
      for (var s in services) {
        for (var c in s.characteristics) {
          if (c.properties.notify || c.properties.read) {
            _rxChar = c;
          }
          if (c.properties.write || c.properties.writeWithoutResponse) {
            _txChar = c;
          }
          if (_rxChar != null && _txChar != null) break;
        }
        if (_rxChar != null && _txChar != null) break;
      }

      if (_rxChar == null) {
        // subscribe to any notify characteristic if available
        for (var s in services) {
          for (var c in s.characteristics) {
            if (c.properties.notify) {
              _rxChar = c;
              break;
            }
          }
          if (_rxChar != null) break;
        }
      }

      if (_rxChar == null) {
        // no readable/notify char found
        await disconnect();
        return false;
      }

      // enable notifications
      await _rxChar!.setNotifyValue(true);
      _rxChar!.value.listen((bytes) {
        try {
          final s = utf8.decode(bytes).trim();
          if (s.isNotEmpty) _controller.add(s);
        } catch (e) {
          if (kDebugMode) print('BLE: decode error $e');
        }
      });

      _setConnected(true);

      return true;
    } catch (e) {
      if (kDebugMode) print('BLE connect error: $e');
      await disconnect();
      return false;
    }
  }

  /// Connect to a specific device selected by the user.
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await disconnect();
      _device = device;
      await _device!.connect();
      final services = await _device!.discoverServices();
      // reuse characteristic discovery from scanAndConnect
      for (var s in services) {
        for (var c in s.characteristics) {
          if (_rxChar == null && (c.properties.notify || c.properties.read)) {
            _rxChar = c;
          }
          if (_txChar == null &&
              (c.properties.write || c.properties.writeWithoutResponse)) {
            _txChar = c;
          }
          if (_rxChar != null && _txChar != null) break;
        }
        if (_rxChar != null && _txChar != null) break;
      }

      if (_rxChar == null) {
        await disconnect();
        return false;
      }

      await _rxChar!.setNotifyValue(true);
      _rxChar!.value.listen((bytes) {
        try {
          final s = utf8.decode(bytes).trim();
          if (s.isNotEmpty) _controller.add(s);
        } catch (e) {
          if (kDebugMode) print('BLE: decode error $e');
        }
      });

      _setConnected(true);

      return true;
    } catch (e) {
      if (kDebugMode) print('connectToDevice error: $e');
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      if (_rxChar != null) {
        await _rxChar!.setNotifyValue(false);
        _rxChar = null;
      }
    } catch (_) {}
    try {
      if (_device != null) {
        await _device!.disconnect();
        _device = null;
        _setConnected(false);
      }
    } catch (_) {}
  }

  void _setConnected(bool v) {
    _connected = v;
    _connectionController.add(v);
    if (!v && _autoReconnect) _scheduleReconnect();
    if (v && _reconnectTimer != null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
  }

  void startAutoReconnect() {
    _autoReconnect = true;
    if (!_connected) _scheduleReconnect();
  }

  void stopAutoReconnect() {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // simple backoff: try after 3s
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (_device == null) return;
      try {
        final ok = await connectToDevice(_device!);
        if (!ok) {
          // try again
          _scheduleReconnect();
        }
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  Future<bool> sendCommand(String text) async {
    if (_txChar == null) return false;
    try {
      final payload = text.endsWith('\n') ? text : '$text\n';
      final bytes = utf8.encode(payload);
      await _txChar!.write(
        bytes,
        withoutResponse: _txChar!.properties.writeWithoutResponse,
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('BLE write error: $e');
      return false;
    }
  }

  void dispose() {
    _controller.close();
    _connectionController.close();
    _reconnectTimer?.cancel();
  }
}
