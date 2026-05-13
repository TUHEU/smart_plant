#include <SoftwareSerial.h>
#include <DHT.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// --- PIN DEFINITIONS ---
// Analog Pins
const int moisturePin = A0;
const int waterLevelPin = A1;
const int ldrPin = A2;

// Digital Pins
const int btRxPin = 2; // Connect to HC-05 TX
const int btTxPin = 3; // Connect to HC-05 RX
const int dhtPin = 4;
const int relayPin = 5;
const int ds18b20Pin = 6;
const int pirPin = 7;
const int greenLedPin = 8;
const int redLedPin = 9;
const int buzzerPin = 10;

// --- SENSOR INITIALIZATION ---
#define DHTTYPE DHT11
DHT dht(dhtPin, DHTTYPE);

OneWire oneWire(ds18b20Pin);
DallasTemperature soilTemp(&oneWire);

SoftwareSerial btSerial(btRxPin, btTxPin);

void setup() {
  Serial.begin(9600);     // For computer Serial Monitor debugging
  btSerial.begin(9600);   // For HC-05 Bluetooth transmission

  dht.begin();
  soilTemp.begin();

  // Configure Pin Modes
  pinMode(relayPin, OUTPUT);
  pinMode(greenLedPin, OUTPUT);
  pinMode(redLedPin, OUTPUT);
  pinMode(buzzerPin, OUTPUT);
  pinMode(pirPin, INPUT);

  // Ensure pump is OFF at startup (Assuming Active LOW relay)
  digitalWrite(relayPin, HIGH);
}

void loop() {
  // 1. READ ANALOG SENSORS (Map to 0-100%)
  // Note: Calibration values (1023 and 0) may need adjustment based on your dry/wet tests
  int moistureRaw = analogRead(moisturePin);
  int moisturePercent = map(moistureRaw, 1023, 0, 0, 100);
  moisturePercent = constrain(moisturePercent, 0, 100);

  int waterLevelRaw = analogRead(waterLevelPin);
  int waterLevelPercent = map(waterLevelRaw, 0, 1023, 0, 100);
  waterLevelPercent = constrain(waterLevelPercent, 0, 100);

  int lightLevelRaw = analogRead(ldrPin);
  int lightPercent = map(lightLevelRaw, 0, 1023, 0, 100);

  // 2. READ DIGITAL SENSORS
  float airTemp = dht.readTemperature();
  float airHumid = dht.readHumidity();

  soilTemp.requestTemperatures();
  float soilTemperature = soilTemp.getTempCByIndex(0);

  int motionDetected = digitalRead(pirPin);

  // 3. HYSTERESIS LOGIC & ACTUATION
  bool isWatering = false;
  bool isTankEmpty = (waterLevelPercent <= 10);

  // Trigger ON condition
  if (moisturePercent < 30 && !isTankEmpty) {
    digitalWrite(relayPin, LOW); // Turn Pump ON
    isWatering = true;

    // Status Indicators
    digitalWrite(greenLedPin, HIGH);
    digitalWrite(redLedPin, LOW);
    digitalWrite(buzzerPin, LOW);
  }
  // Trigger OFF condition
  else if (moisturePercent >= 70 || isTankEmpty) {
    digitalWrite(relayPin, HIGH); // Turn Pump OFF
    isWatering = false;

    // Fail-Safe Alert Check
    if (isTankEmpty) {
      digitalWrite(redLedPin, HIGH); // Error state
      digitalWrite(greenLedPin, LOW);
      digitalWrite(buzzerPin, HIGH); // Sound alarm
    } else {
      digitalWrite(redLedPin, LOW);
      digitalWrite(greenLedPin, HIGH); // Healthy idle state
      digitalWrite(buzzerPin, LOW);
    }
  }

  // 4. BLUETOOTH DATA TRANSMISSION
  // Format: "Moisture,WaterLevel,AirTemp,AirHumid,SoilTemp,Light,Motion,PumpStatus"
  String payload = String(moisturePercent) + "," +
                   String(waterLevelPercent) + "," +
                   String(airTemp) + "," +
                   String(airHumid) + "," +
                   String(soilTemperature) + "," +
                   String(lightPercent) + "," +
                   String(motionDetected) + "," +
                   String(isWatering ? 1 : 0);

  btSerial.println(payload); // Send to Flutter
  Serial.println(payload);   // Mirror to Serial Monitor

  delay(2000); // 2-second polling interval
}
