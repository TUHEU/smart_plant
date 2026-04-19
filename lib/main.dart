import 'dart:async';
import 'dart:math';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'services/bluetooth_service.dart';
import 'services/serial_service.dart';
import 'theme.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────
void main() {
  runApp(const SmartPlantApp());
}

class SmartPlantApp extends StatelessWidget {
  const SmartPlantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergence-Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.light,
        ),
      ),
      home: const PlantDashboard(),
    );
  }
}

// ─────────────────────────────────────────────
// DATA MODEL  (from Code 2)
// Parses Arduino comma-separated string:
// "moisture,temp,light,airQuality,metalLevel"
// ─────────────────────────────────────────────
class PlantData {
  final double moisture;
  final double temp;
  final int light;
  final int airQuality;
  final int metalLevel;

  const PlantData({
    required this.moisture,
    required this.temp,
    required this.light,
    required this.airQuality,
    required this.metalLevel,
  });

  // Default demo values while not connected to hardware
  factory PlantData.demo() => const PlantData(
    moisture: 35.0,
    temp: 24.0,
    light: 80,
    airQuality: 90,
    metalLevel: 12,
  );

  /// Parses a raw Arduino string like "35.0,24.5,80,120,12"
  factory PlantData.fromRawString(String raw) {
    final parts = raw.split(',').map((s) => s.trim()).toList();
    double pDouble(int i) =>
        double.tryParse(parts.elementAtOrDefault(i, '0')) ?? 0.0;
    int pInt(int i) => int.tryParse(parts.elementAtOrDefault(i, '0')) ?? 0;

    return PlantData(
      moisture: pDouble(0),
      temp: pDouble(1),
      light: pInt(2),
      airQuality: pInt(3),
      metalLevel: pInt(4),
    );
  }

  // ── Derived helpers ──────────────────────────
  String get moistureLabel => '${moisture.toInt()}%';
  String get tempLabel => '${temp.toStringAsFixed(1)}°C';
  String get lightLabel => '$light%';
  String get airQualityLabel {
    if (airQuality >= 80) return 'Good';
    if (airQuality >= 50) return 'Fair';
    return 'Poor';
  }

  String get metalLabel {
    if (metalLevel < 20) return 'Low';
    if (metalLevel < 60) return 'Moderate';
    return 'High';
  }

  // ── Health status ────────────────────────────
  PlantStatus get status {
    if (temp > 35) return PlantStatus.overheating;
    if (moisture < 30) return PlantStatus.needsWater;
    return PlantStatus.healthy;
  }
}

// Helper extension for safe list access
extension _SafeList<T> on List<T> {
  T elementAtOrDefault(int index, T defaultValue) =>
      index < length ? this[index] : defaultValue;
}

enum PlantStatus { healthy, needsWater, overheating }

// ─────────────────────────────────────────────
// DASHBOARD SCREEN  (merged Code 1 + Code 3)
// ─────────────────────────────────────────────
class PlantDashboard extends StatefulWidget {
  const PlantDashboard({super.key});

  @override
  State<PlantDashboard> createState() => _PlantDashboardState();
}

class _PlantDashboardState extends State<PlantDashboard>
    with SingleTickerProviderStateMixin {
  // ── State ────────────────────────────────────
  PlantData _data = PlantData.demo();
  bool _isPumpOn = false;
  bool _connected = false; // true when Bluetooth/Wi-Fi link is live
  late AnimationController _pulseController;
  late final BleService _bleService;
  late final SerialService _serialService;
  StreamSubscription<String>? _bleSub;
  StreamSubscription<String>? _serialSub;
  StreamSubscription<bool>? _bleConnSub;

  // Simulate incoming Arduino data every 3 seconds (replace with real BT stream)
  Timer? _simulationTimer;

  void _startSimulation() {
    _simulationTimer?.cancel();
    if (_connected) return;
    _simulationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final rng = Random();
      final rawString =
          '${(30 + rng.nextDouble() * 40).toStringAsFixed(1)},' // moisture
          '${(20 + rng.nextDouble() * 20).toStringAsFixed(1)},' // temp
          '${50 + rng.nextInt(50)},' // light
          '${60 + rng.nextInt(40)},' // air quality
          '${rng.nextInt(30)}'; // metal level

      _onDataReceived(rawString);
    });
  }

  void _setConnected(bool connected) {
    setState(() {
      _connected = connected;
      if (connected) {
        _simulationTimer?.cancel();
        _simulationTimer = null;
      } else {
        _startSimulation();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    // BLE service
    _bleService = BleService();
    _serialService = SerialService();
    // listen for BLE incoming packets (will be quiet until connected)
    _bleSub = _bleService.dataStream.listen(
      (raw) {
        _onDataReceived(raw);
      },
      onError: (e) {
        debugPrint('BLE stream error: $e');
      },
    );

    // listen for connection state changes to update UI and handle auto-reconnect UX
    _bleConnSub = _bleService.connectionStream.listen((connected) {
      if (mounted) {
        if (!connected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth disconnected — attempting reconnect'),
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Bluetooth connected')));
        }
        _setConnected(connected);
      }
    });

    // serial stream (inactive until user opens a port)
    _serialSub = _serialService.dataStream.listen(
      (raw) {
        _onDataReceived(raw);
      },
      onError: (e) {
        debugPrint('Serial stream error: $e');
      },
    );

    // Request permissions then start demo simulation (cancelled when connected)
    _requestPermissions().then((granted) {
      if (!granted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bluetooth permissions required')),
          );
        });
      }
      _startSimulation();
    });

    _loadCalibration();
  }

  Future<bool> _requestPermissions() async {
    try {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      final location = await Permission.locationWhenInUse.request();
      if (scan.isPermanentlyDenied ||
          connect.isPermanentlyDenied ||
          location.isPermanentlyDenied) {
        // Let user open app settings to enable permissions
        await openAppSettings();
        return false;
      }
      return scan.isGranted && connect.isGranted && location.isGranted;
    } catch (e) {
      debugPrint('Permission request error: $e');
      return false;
    }
  }

  // calibration storage
  late SharedPreferences _prefs;
  double _moistureMin = 300.0;
  double _moistureMax = 700.0;

  Future<void> _loadCalibration() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _moistureMin = _prefs.getDouble('moisture_min') ?? 300.0;
      _moistureMax = _prefs.getDouble('moisture_max') ?? 700.0;
    });
  }

  Future<void> _saveCalibration(double min, double max) async {
    await _prefs.setDouble('moisture_min', min);
    await _prefs.setDouble('moisture_max', max);
    setState(() {
      _moistureMin = min;
      _moistureMax = max;
    });
    // send calibration to device as a simple CSV command: CAL,moistMin,moistMax
    final cmd = 'CAL,${min.toStringAsFixed(1)},${max.toStringAsFixed(1)}';
    await _bleService.sendCommand(cmd);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _simulationTimer?.cancel();
    _bleSub?.cancel();
    _serialSub?.cancel();
    _bleConnSub?.cancel();
    _bleService.dispose();
    _serialService.dispose();
    super.dispose();
  }

  /// Called whenever a new data packet arrives from the Arduino
  void _onDataReceived(String rawString) {
    setState(() {
      _data = PlantData.fromRawString(rawString);
    });
  }

  /// Sends pump command to Arduino ('W' = on, 'w' = off)
  void _onPumpToggle(bool value) {
    setState(() => _isPumpOn = value);
    final command = value ? 'W' : 'w';
    debugPrint('[Arduino TX] $command'); // Replace with actual BT write
    _bleService.sendCommand(command).then((ok) {
      if (!ok) debugPrint('Failed to send pump command over BLE');
    });
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // ── Health Banner (Code 3 logic) ──────────────
            _HealthBanner(data: _data, pulse: _pulseController),
            const SizedBox(height: 8),

            // ── Sensor Grid ───────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  children: [
                    _SensorCard(
                      title: 'Moisture',
                      value: _data.moistureLabel,
                      icon: Icons.water_drop_rounded,
                      color: const Color(0xFF0077B6),
                      progress: _data.moisture / 100,
                    ),
                    _SensorCard(
                      title: 'Temperature',
                      value: _data.tempLabel,
                      icon: Icons.thermostat_rounded,
                      color: const Color(0xFFE76F51),
                      progress: _data.temp / 50,
                      alert: _data.temp > 35,
                    ),
                    _SensorCard(
                      title: 'Light',
                      value: _data.lightLabel,
                      icon: Icons.wb_sunny_rounded,
                      color: const Color(0xFFE9C46A),
                      progress: _data.light / 100,
                    ),
                    _SensorCard(
                      title: 'Air Quality',
                      value: _data.airQualityLabel,
                      icon: Icons.air_rounded,
                      color: const Color(0xFF2D6A4F),
                      progress: _data.airQuality / 100,
                    ),
                    _SensorCard(
                      title: 'Metal Content',
                      value: _data.metalLabel,
                      icon: Icons.precision_manufacturing_rounded,
                      color: const Color(0xFF6C757D),
                      progress: _data.metalLevel / 100,
                    ),
                    _SensorCard(
                      title: 'Water Level',
                      value: 'High',
                      icon: Icons.water_rounded,
                      color: const Color(0xFF48CAE4),
                      progress: 0.82,
                    ),
                  ],
                ),
              ),
            ),

            // ── Manual Override (Code 1 + Code 3) ─────────
            _ManualControl(isPumpOn: _isPumpOn, onToggle: _onPumpToggle),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: const Row(
        children: [
          Icon(Icons.eco_rounded, size: 22),
          SizedBox(width: 8),
          Text(
            'Emergence-Connect',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      backgroundColor: kPrimaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        // Connection indicator
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Icon(
              _connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: _connected
                  ? Color.lerp(
                      Colors.white,
                      Colors.lightGreenAccent,
                      _pulseController.value,
                    )
                  : Colors.white38,
              size: 22,
            ),
          ),
        ),
        // Device picker / connect button
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: 'Devices',
            icon: Icon(
              _connected ? Icons.link_off : Icons.bluetooth_searching,
              color: Colors.white,
            ),
            onPressed: () async {
              if (_connected) {
                _bleService.stopAutoReconnect();
                await _bleService.disconnect();
                await _serialService.close();
                _setConnected(false);
                return;
              }

              final granted = await _requestPermissions();
              if (!mounted) return;
              if (!granted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bluetooth permissions required'),
                  ),
                );
                return;
              }

              // show device picker (BLE results + manual serial option)
              await showModalBottomSheet(
                context: context,
                builder: (_) => SizedBox(
                  height: 420,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.usb),
                        title: const Text('Open Serial Port (manual)'),
                        subtitle: const Text('Enter COM port, e.g. COM3'),
                        onTap: () async {
                          Navigator.of(context).pop();
                          final portName = await showDialog<String>(
                            context: context,
                            builder: (ctx) {
                              String value = '';
                              return AlertDialog(
                                title: const Text('Serial Port'),
                                content: TextField(
                                  decoration: const InputDecoration(
                                    hintText: 'COM3 or /dev/ttyUSB0',
                                  ),
                                  onChanged: (v) => value = v.trim(),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(null),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(value),
                                    child: const Text('Open'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (portName != null && portName.isNotEmpty) {
                            final ok = _serialService.open(portName);
                            _setConnected(ok);
                            if (!ok && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to open serial port'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      const Divider(),
                      Expanded(
                        child: StreamBuilder<List<ScanResult>>(
                          stream: FlutterBluePlus.scanResults,
                          builder: (c, s) {
                            if (!s.hasData) {
                              FlutterBluePlus.startScan(
                                timeout: const Duration(seconds: 4),
                              );
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final results = s.data!;
                            if (results.isEmpty) {
                              return const Center(
                                child: Text('No devices found'),
                              );
                            }
                            return ListView(
                              children: results.map((r) {
                                final name = r.device.name.isNotEmpty
                                    ? r.device.name
                                    : r.device.id.id;
                                return ListTile(
                                  title: Text(name),
                                  subtitle: Text(r.device.id.id),
                                  onTap: () async {
                                    final nav = Navigator.of(context);
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    await FlutterBluePlus.stopScan();
                                    nav.pop();
                                    final ok = await _bleService
                                        .connectToDevice(r.device);
                                    if (!mounted) return;
                                    if (ok) {
                                      _bleService.startAutoReconnect();
                                      _setConnected(true);
                                    } else {
                                      _setConnected(false);
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('Failed to connect'),
                                        ),
                                      );
                                    }
                                  },
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Calibration button
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: 'Calibration',
            icon: const Icon(Icons.tune, color: Colors.white),
            onPressed: () async {
              final res = await showDialog<bool>(
                context: context,
                builder: (_) =>
                    _CalibrationDialog(min: _moistureMin, max: _moistureMax),
              );
              if (!mounted) return;
              if (res == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Calibration saved')),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// HEALTH BANNER WIDGET  (Code 3 logic, enhanced)
// ─────────────────────────────────────────────
class _HealthBanner extends StatelessWidget {
  final PlantData data;
  final AnimationController pulse;

  const _HealthBanner({required this.data, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final (String label, Color color, IconData icon) = switch (data.status) {
      PlantStatus.needsWater => (
        'Needs Water 💧',
        const Color(0xFFE63946),
        Icons.water_drop_outlined,
      ),
      PlantStatus.overheating => (
        'Overheating ⚠️',
        const Color(0xFFFF6B35),
        Icons.thermostat_outlined,
      ),
      PlantStatus.healthy => (
        'Plant is Healthy ✅',
        const Color(0xFF2D6A4F),
        Icons.check_circle_outline,
      ),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // animated icon pulse
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) =>
                Icon(icon, color: Colors.white, size: 18 + 6 * pulse.value),
          ),
          const SizedBox(width: 10),
          Text(
            'Status: $label',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// Simple calibration dialog for moisture sensor
class _CalibrationDialog extends StatefulWidget {
  final double min;
  final double max;
  const _CalibrationDialog({required this.min, required this.max});

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  late double _min;
  late double _max;

  @override
  void initState() {
    super.initState();
    _min = widget.min;
    _max = widget.max;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Moisture Calibration'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Dry (ADC): ${_min.toStringAsFixed(0)}'),
          Slider(
            value: _min,
            min: 0,
            max: 1023,
            onChanged: (v) => setState(() => _min = v),
          ),
          const SizedBox(height: 8),
          Text('Wet (ADC): ${_max.toStringAsFixed(0)}'),
          Slider(
            value: _max,
            min: 0,
            max: 1023,
            onChanged: (v) => setState(() => _max = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            // save values via parent state
            final nav = Navigator.of(context);
            final state = context
                .findAncestorStateOfType<_PlantDashboardState>();
            if (state != null) {
              await state._saveCalibration(_min, _max);
            }
            if (!mounted) return;
            nav.pop(true);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// SENSOR CARD WIDGET  (Code 1 + Code 3, merged)
// ─────────────────────────────────────────────
class _SensorCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double progress; // 0.0 – 1.0
  final bool alert; // shows red pulse ring when true

  const _SensorCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.progress,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: alert
            ? Border.all(color: Colors.redAccent.withOpacity(0.7), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon bubble
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),

          // Value (large, bold)
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: alert ? Colors.redAccent : const Color(0xFF1B1B2F),
            ),
          ),
          const SizedBox(height: 10),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0).toDouble(),
              minHeight: 6,
              color: alert ? Colors.redAccent : color,
              backgroundColor: color.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// MANUAL PUMP CONTROL  (Code 1 + Code 3)
// ─────────────────────────────────────────────
class _ManualControl extends StatelessWidget {
  final bool isPumpOn;
  final ValueChanged<bool> onToggle;

  const _ManualControl({required this.isPumpOn, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          secondary: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPumpOn
                  ? const Color(0xFF0077B6).withOpacity(0.15)
                  : Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPumpOn ? Icons.water_rounded : Icons.water_outlined,
              color: isPumpOn ? const Color(0xFF0077B6) : Colors.grey,
              size: 24,
            ),
          ),
          title: Text(
            'Manual Pump Override',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: isPumpOn
                  ? const Color(0xFF0077B6)
                  : const Color(0xFF1B1B2F),
            ),
          ),
          subtitle: Text(
            isPumpOn ? 'Pump is RUNNING' : 'Bypass sensor logic',
            style: TextStyle(
              fontSize: 12,
              color: isPumpOn ? const Color(0xFF0077B6) : Colors.grey[500],
            ),
          ),
          value: isPumpOn,
          activeColor: const Color(0xFF0077B6),
          onChanged: onToggle,
          // Sends 'W' (on) or 'w' (off) to Arduino via BT
        ),
      ),
    );
  }
}
