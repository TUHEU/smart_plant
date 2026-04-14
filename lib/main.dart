import 'dart:async';
import 'dart:math';
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
    final parts = raw.split(',');
    return PlantData(
      moisture: double.tryParse(parts.elementAtOrDefault(0, '0')) ?? 0,
      temp: double.tryParse(parts.elementAtOrDefault(1, '0')) ?? 0,
      light: int.tryParse(parts.elementAtOrDefault(2, '0')) ?? 0,
      airQuality: int.tryParse(parts.elementAtOrDefault(3, '0')) ?? 0,
      metalLevel: int.tryParse(parts.elementAtOrDefault(4, '0')) ?? 0,
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

  // Simulate incoming Arduino data every 3 seconds (replace with real BT stream)
  Timer? _simulationTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // ── Demo simulation (remove when wiring real Bluetooth) ──
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

  @override
  void dispose() {
    _pulseController.dispose();
    _simulationTimer?.cancel();
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
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F1),
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
      backgroundColor: const Color(0xFF2D6A4F),
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        // Connection indicator
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Icon(
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
          Icon(icon, color: Colors.white, size: 20),
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
              value: progress.clamp(0.0, 1.0),
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
