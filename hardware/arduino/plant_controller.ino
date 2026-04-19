#include <EEPROM.h>
#include "DHT.h" // Ensure you have the DHT sensor library installed

// Pin Definitions
const int pumpPin = 7; 
const int waterLvlPin = 8; 
const int moisturePin = A0;
const int ldrPin = A1;
const int mq135Pin = A2;
const int metalPin = A3;
const int DHTPIN = 2; // Pin for DHT11

#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

// Calibration & Timing
float moisture_min = 300.0;
float moisture_max = 700.0;
unsigned long previousMillis = 0;
const long interval = 2000; 

// EEPROM layout
const int ADDR_MOIST_MIN = 0;
const int ADDR_MOIST_MAX = ADDR_MOIST_MIN + sizeof(float);
const int ADDR_MAGIC = ADDR_MOIST_MAX + sizeof(float);
const uint32_t EEPROM_MAGIC = 0xA5A5A5A5;

void setup() {
  Serial.begin(9600);
  dht.begin();
  pinMode(pumpPin, OUTPUT);
  pinMode(waterLvlPin, INPUT_PULLUP);
  digitalWrite(pumpPin, LOW);

  // EEPROM Logic
  uint32_t magic = 0;
  EEPROM.get(ADDR_MAGIC, magic);
  if (magic == EEPROM_MAGIC) {
    EEPROM.get(ADDR_MOIST_MIN, moisture_min);
    EEPROM.get(ADDR_MOIST_MAX, moisture_max);
  }
}

void loop() {
  unsigned long currentMillis = millis();

  // 1. NON-BLOCKING SENSOR BROADCAST
  if (currentMillis - previousMillis >= interval) {
    previousMillis = currentMillis;
    
    // Physical Readings
    int rawAdc = analogRead(moisturePin);
    float moisturePerc = constrain(((rawAdc - moisture_min) / (moisture_max - moisture_min)) * 100.0, 0.0, 100.0);
    float temp = dht.readTemperature();
    int light = analogRead(ldrPin);
    int airQ = analogRead(mq135Pin);
    int metal = analogRead(metalPin);

    // CSV format for Flutter
    Serial.print(moisturePerc, 1); Serial.print(",");
    Serial.print(temp, 1);        Serial.print(",");
    Serial.print(light);          Serial.print(",");
    Serial.print(airQ);           Serial.print(",");
    Serial.println(metal);
  }

  // 2. FAST COMMAND HANDLING (No readStringUntil delay)
  if (Serial.available()) {
    char cmd = Serial.read(); 
    
    if (cmd == 'W') { // Pump ON
      if (waterAvailable()) {
        digitalWrite(pumpPin, HIGH);
        Serial.println("STATUS:PUMP_ON");
      } else {
        Serial.println("ERR:NO_WATER");
      }
    } 
    else if (cmd == 'w') { // Pump OFF
      digitalWrite(pumpPin, LOW);
      Serial.println("STATUS:PUMP_OFF");
    }
    // Note: Complex CAL commands should be handled via a buffer if needed
  }
}

bool waterAvailable() {
  // Assuming float switch pulls to GND when water is LOW
  return digitalRead(waterLvlPin) == HIGH; 
}