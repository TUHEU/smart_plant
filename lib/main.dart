import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() {
  runApp(FarmLinkApp());
}

class FarmLinkApp extends StatelessWidget {
  const FarmLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Plant Monitor',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.transparent, // Allow web CSS background to show
        cardColor: Colors.white,
        fontFamily: 'Roboto',
      ),
      home: DashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- DATA MODEL ---
class PlantData {
  final int moisture;
  final int waterLevel;
  final double airTemp;
  final double airHumid;
  final double soilTemp;
  final int light;
  final int motion;
  final int pumpStatus;

  PlantData({
    required this.moisture,
    required this.waterLevel,
    required this.airTemp,
    required this.airHumid,
    required this.soilTemp,
    required this.light,
    required this.motion,
    required this.pumpStatus,
  });

  factory PlantData.fromRawString(String raw) {
    List<String> parts = raw.split(',');
    if (parts.length != 8) throw FormatException('Invalid data stream');
    
    return PlantData(
      moisture: int.parse(parts[0]),
      waterLevel: int.parse(parts[1]),
      airTemp: double.parse(parts[2]),
      airHumid: double.parse(parts[3]),
      soilTemp: double.parse(parts[4]),
      light: int.parse(parts[5]),
      motion: int.parse(parts[6]),
      pumpStatus: int.parse(parts[7]),
    );
  }
}

// --- UI DASHBOARD ---
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  // Bluetooth Variables
  BluetoothConnection? connection;
  String _messageBuffer = '';
  bool isConnected = false;
  
  // App State Variables
  bool isManualOverride = false;

  // Initial dummy data
  PlantData currentData = PlantData(
    moisture: 0, waterLevel: 0, airTemp: 0.0, 
    airHumid: 0.0, soilTemp: 0.0, light: 0, motion: 0, pumpStatus: 0
  );

  @override
  void initState() {
    super.initState();
    _connectToHC05(); 
  }

  void _connectToHC05() async {
    // PUT YOUR ACTUAL HC-05 MAC ADDRESS HERE
    String macAddress = "98:D3:31:FD:XX:XX"; 

    try {
      connection = await BluetoothConnection.toAddress(macAddress);
      setState(() { isConnected = true; });

      connection!.input!.listen((Uint8List data) {
        String incomingText = ascii.decode(data);
        _messageBuffer += incomingText;

        if (_messageBuffer.contains('\n')) {
          List<String> lines = _messageBuffer.split('\n');
          _messageBuffer = lines.last;
          
          String completeString = lines.first.trim();
          if (completeString.isNotEmpty) {
            updateData(completeString);
          }
        }
      }).onDone(() {
        setState(() { isConnected = false; });
      });
    } catch (e) {
      debugPrint('Cannot connect: $e');
    }
  }

  void updateData(String incomingString) {
    setState(() {
      try {
        currentData = PlantData.fromRawString(incomingString);
      } catch (e) {
        debugPrint("Data parsing error: $e");
      }
    });
  }

  // --- MANUAL OVERRIDE FUNCTION ---
  void _togglePump(bool value) {
    setState(() {
      isManualOverride = value;
    });

    if (isConnected && connection != null) {
      // Send '1' to turn ON, '0' to turn OFF
      String command = value ? "1" : "0";
      connection!.output.add(ascii.encode(command));
    }
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isTankEmpty = currentData.waterLevel <= 10;
    // The pump is active if the Arduino says it's active OR if we manually turned it on
    bool isPumpActive = (currentData.pumpStatus == 1) || isManualOverride;

    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Plant Monitor', style: TextStyle(fontWeight: FontWeight.w300, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20.0),
            child: Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: isConnected ? Colors.blueAccent : Colors.redAccent,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Plant Status", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isTankEmpty ? Colors.redAccent.withValues(alpha: 0.2) : Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isTankEmpty ? Colors.redAccent : Colors.greenAccent),
                    ),
                    child: Text(
                      isTankEmpty ? '⚠️ TANK EMPTY - PUMP DISABLED' : '✔️ SYSTEM OPTIMAL',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Override Control Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
              child: Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isPumpActive 
                        ? [Color(0xFF00B4DB), Color(0xFF0083B0)] // Active Blue Gradient
                        : [Color(0xFF2C3E50), Color(0xFF1E1E1E)], // Idle Dark Gradient
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: isPumpActive ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.black26, blurRadius: 15, offset: Offset(0, 5))
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Water Pump", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text(isPumpActive ? "Irrigating..." : "Standby"),
                      ],
                    ),
                    // The Override Switch
                    Switch(
                      value: isManualOverride,
                      onChanged: isTankEmpty ? null : _togglePump, // Disable switch if tank is empty
                      activeThumbColor: Colors.white,
                      activeTrackColor: Colors.blue[300],
                      inactiveThumbColor: Colors.grey[400],
                      inactiveTrackColor: Colors.grey[700],
                    ),
                  ],
                ),
              ),
            ),

            // Metrics Grid
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.1, // Makes cards slightly wider
                children: [
                  _buildModernCard("Soil Moisture", "${currentData.moisture}%", Icons.water_drop, Colors.lightBlueAccent),
                  _buildModernCard("Tank Level", "${currentData.waterLevel}%", Icons.waves, Colors.tealAccent),
                  _buildModernCard("Air Temp", "${currentData.airTemp}°C", Icons.thermostat, Colors.orangeAccent),
                  _buildModernCard("Humidity", "${currentData.airHumid}%", Icons.cloud, Colors.blueGrey),
                  _buildModernCard("Soil Temp", "${currentData.soilTemp}°C", Icons.grass, Colors.lightGreenAccent),
                  _buildModernCard("Light", "${currentData.light}%", Icons.wb_sunny, Colors.amberAccent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method for beautiful cards
  Widget _buildModernCard(String title, String value, IconData icon, Color iconColor) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}