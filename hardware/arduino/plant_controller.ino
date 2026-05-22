/*
 * ============================================================
 *  FARMLINK - Smart Plant Monitoring System
 *  Arduino UNO Firmware v2.0
 * ============================================================
 *  WIRING SUMMARY (see full guide below):
 *  A0 -> Soil Moisture Sensor (AOUT)
 *  A1 -> Water Level Sensor (Signal)
 *  A2 -> LDR (via 10kΩ voltage divider to GND)
 *  D2 -> HC-05 TX  (SoftwareSerial RX)
 *  D3 -> HC-05 RX  (SoftwareSerial TX) [use voltage divider!]
 *  D4 -> DHT11 Data
 *  D5 -> Relay Signal (Active LOW)
 *  D6 -> DS18B20 Data (with 4.7kΩ pull-up to 5V)
 *  D7 -> PIR Sensor OUT
 *  D8 -> Green LED (via 220Ω)
 *  D9 -> Red LED   (via 220Ω)
 *  D10-> Active Buzzer (+)
 * ============================================================
 */

#include <SoftwareSerial.h>
#include <DHT.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// ── PIN DEFINITIONS ─────────────────────────────────────────
const int moisturePin  = A0;
const int waterLevPin  = A1;
const int ldrPin       = A2;

const int btRxPin      = 2;   // HC-05 TX → Arduino D2
const int btTxPin      = 3;   // HC-05 RX → Arduino D3
const int dhtPin       = 4;
const int relayPin     = 5;
const int ds18Pin      = 6;
const int pirPin       = 7;
const int greenLedPin  = 8;
const int redLedPin    = 9;
const int buzzerPin    = 10;

// ── SENSOR OBJECTS ───────────────────────────────────────────
#define DHTTYPE DHT11
DHT            dht(dhtPin, DHTTYPE);
OneWire        oneWire(ds18Pin);
DallasTemperature soilSensor(&oneWire);
SoftwareSerial btSerial(btRxPin, btTxPin);

// ── HYSTERESIS THRESHOLDS ────────────────────────────────────
const int MOISTURE_ON      = 30;   // % — pump turns ON  below this
const int MOISTURE_OFF     = 70;   // % — pump turns OFF above this
const int WATER_LOW_THRESH = 10;   // % — tank "empty" threshold

// ── STATE ────────────────────────────────────────────────────
bool isManualOverride = false;
bool pumpOn           = false;

// ── TIMING ───────────────────────────────────────────────────
unsigned long lastSendMillis = 0;
const unsigned long SEND_INTERVAL = 2000; // ms

// ─────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(9600);
  btSerial.begin(9600);

  dht.begin();
  soilSensor.begin();

  pinMode(relayPin,    OUTPUT);
  pinMode(greenLedPin, OUTPUT);
  pinMode(redLedPin,   OUTPUT);
  pinMode(buzzerPin,   OUTPUT);
  pinMode(pirPin,      INPUT);

  // Pump OFF at startup (Active-LOW relay: HIGH = OFF)
  digitalWrite(relayPin, HIGH);
  digitalWrite(greenLedPin, HIGH); // Steady green = system ready
  delay(500);
  digitalWrite(greenLedPin, LOW);
}

// ─────────────────────────────────────────────────────────────
void loop() {

  // ── 1. CHECK FOR INCOMING BLUETOOTH COMMANDS ─────────────
  if (btSerial.available()) {
    char cmd = btSerial.read();
    if (cmd == '1') {
      isManualOverride = true;          // App says: PUMP ON
    } else if (cmd == '0') {
      isManualOverride = false;         // App says: PUMP OFF
    }
  }

  // ── 2. READ SENSORS ───────────────────────────────────────
  int moistureRaw     = analogRead(moisturePin);
  int moisturePercent = constrain(map(moistureRaw, 1023, 0, 0, 100), 0, 100);

  int waterRaw        = analogRead(waterLevPin);
  int waterPercent    = constrain(map(waterRaw, 0, 1023, 0, 100), 0, 100);

  int lightRaw        = analogRead(ldrPin);
  int lightPercent    = constrain(map(lightRaw, 0, 1023, 0, 100), 0, 100);

  float airTemp  = dht.readTemperature();
  float airHumid = dht.readHumidity();
  if (isnan(airTemp))  airTemp  = -1.0;
  if (isnan(airHumid)) airHumid = -1.0;

  soilSensor.requestTemperatures();
  float soilTemperature = soilSensor.getTempCByIndex(0);
  if (soilTemperature == DEVICE_DISCONNECTED_C) soilTemperature = -1.0;

  int motionDetected = digitalRead(pirPin);

  bool isTankEmpty = (waterPercent <= WATER_LOW_THRESH);

  // ── 3. PUMP HYSTERESIS + MANUAL OVERRIDE LOGIC ───────────
  if (isTankEmpty) {
    // FAIL-SAFE: Tank empty → force pump OFF, no override allowed
    pumpOn = false;
    digitalWrite(relayPin, HIGH);
    digitalWrite(greenLedPin, LOW);
    digitalWrite(redLedPin,   HIGH);
    // Buzzer beeps: 2 short beeps
    for (int i = 0; i < 2; i++) {
      digitalWrite(buzzerPin, HIGH); delay(150);
      digitalWrite(buzzerPin, LOW);  delay(150);
    }

  } else if (isManualOverride) {
    // MANUAL: User forced pump ON from app
    pumpOn = true;
    digitalWrite(relayPin,    LOW);  // Active-LOW: LOW = ON
    digitalWrite(greenLedPin, HIGH);
    digitalWrite(redLedPin,   LOW);
    digitalWrite(buzzerPin,   LOW);

  } else if (!pumpOn && moisturePercent < MOISTURE_ON) {
    // AUTO ON: Soil is dry
    pumpOn = true;
    digitalWrite(relayPin,    LOW);
    digitalWrite(greenLedPin, HIGH);
    digitalWrite(redLedPin,   LOW);
    digitalWrite(buzzerPin,   LOW);

  } else if (pumpOn && moisturePercent >= MOISTURE_OFF) {
    // AUTO OFF: Soil is saturated
    pumpOn = false;
    digitalWrite(relayPin,    HIGH);
    digitalWrite(greenLedPin, HIGH);
    digitalWrite(redLedPin,   LOW);
    digitalWrite(buzzerPin,   LOW);
  }

  // ── 4. TRANSMIT SENSOR DATA VIA BLUETOOTH ─────────────────
  // Non-blocking: only send every SEND_INTERVAL ms
  unsigned long now = millis();
  if (now - lastSendMillis >= SEND_INTERVAL) {
    lastSendMillis = now;

    // CSV Format (8 fields):
    // Moisture,WaterLevel,AirTemp,AirHumid,SoilTemp,Light,Motion,PumpStatus
    String payload =
        String(moisturePercent)  + "," +
        String(waterPercent)     + "," +
        String(airTemp, 1)       + "," +
        String(airHumid, 1)      + "," +
        String(soilTemperature, 1) + "," +
        String(lightPercent)     + "," +
        String(motionDetected)   + "," +
        String(pumpOn ? 1 : 0);

    btSerial.println(payload);  // → Flutter App
    Serial.println(payload);    // → Serial Monitor (debug)
  }
}
