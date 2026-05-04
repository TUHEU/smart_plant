import 'package:flutter/material.dart';
// Data Model for multi-sensor input
class PlantMetrics {
  final double moisture;
  final double temp;
  final int metal;
  final int waterLevel;
  PlantMetrics({
    required this.moisture, required this.temp, 
    required this.metal, required this.waterLevel
  });
  factory PlantMetrics.fromRaw(String data) {
    var parts = data.split(',');
    return PlantMetrics(
      moisture: double.parse(parts[0]),
      temp: double.parse(parts[1]),
      metal: int.parse(parts[2]),
      waterLevel: int.parse(parts[3]),
    );
  }
}
// Main Dashboard Layout
class PlantDashboard extends StatelessWidget {
  const PlantDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("FarmLink IoT Dashboard"), 
        backgroundColor: Colors.green
      ),
      body: Column(
        children: [
          _buildHealthBanner(35.0, 24.0),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: EdgeInsets.all(16),
              children: [
                _sensorCard("Moisture", "35%", Icons.water_drop, Colors.blue),
                _sensorCard("Temp", "24°C", Icons.thermostat, Colors.orange),
                _sensorCard("Metals", "N/A", Icons.memory, Colors.grey),
                _sensorCard("Water Tank", "80%", Icons.waves, Colors.cyan),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _sensorCard(String title, String val, IconData icon, Color col) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: col, size: 40),
          SizedBox(height: 10),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
          Text(val, style: TextStyle(fontSize: 18, color: Colors.grey[700])),
        ],
      ),
    );
  }
  Widget _buildHealthBanner(double m, double t) {
    bool isHealthy = m > 30 && t < 35;
    return Container(
      width: double.infinity,
      color: isHealthy ? Colors.green : Colors.red,
      padding: EdgeInsets.all(12),
      child: Text(
        isHealthy ? "STATUS: HEALTHY" : "ATTENTION REQUIRED",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}