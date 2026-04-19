import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

/// Simple USB-serial fallback service for platforms that expose serial ports.
/// This is optional and may require native platform setup/permissions.
class SerialService {
  final _controller = StreamController<String>.broadcast();
  Stream<String> get dataStream => _controller.stream;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readSub;
  final StringBuffer _buf = StringBuffer();

  /// Try to open a named port (e.g. 'COM3' on Windows).
  bool open(String portName, {int baud = 9600}) {
    try {
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) {
        debugPrint('Serial: failed to open $portName');
        _port = null;
        return false;
      }
      _port!.config.baudRate = baud;
      _reader = SerialPortReader(_port!);
      _readSub = _reader!.stream.listen(
        (data) {
          try {
            final s = utf8.decode(data);
            _buf.write(s);
            while (_buf.toString().contains('\n')) {
              final full = _buf.toString();
              final idx = full.indexOf('\n');
              final line = full.substring(0, idx).trim();
              _buf.clear();
              if (idx + 1 < full.length) _buf.write(full.substring(idx + 1));
              if (line.isNotEmpty) _controller.add(line);
            }
          } catch (e) {
            debugPrint('Serial decode error: $e');
          }
        },
        onError: (e) {
          debugPrint('Serial read error: $e');
        },
      );
      return true;
    } catch (e) {
      debugPrint('Serial open error: $e');
      return false;
    }
  }

  Future<void> close() async {
    try {
      await _readSub?.cancel();
    } catch (_) {}
    try {
      _reader = null;
      _port?.close();
      _port = null;
    } catch (_) {}
  }

  Future<bool> sendCommand(String text) async {
    if (_port == null) return false;
    try {
      final payload = text.endsWith('\n') ? text : '$text\n';
      final bytes = utf8.encode(payload);
      _port!.write(Uint8List.fromList(bytes));
      return true;
    } catch (e) {
      debugPrint('Serial write error: $e');
      return false;
    }
  }

  void dispose() {
    _controller.close();
    close();
  }
}
