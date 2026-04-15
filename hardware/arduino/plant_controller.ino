// Simple Arduino sketch for Smart Plant project
// Sends CSV sensor line over Serial every 2s in format:
// moisture,temp,light,airQuality,metalLevel

const int pumpPin = 7; // relay control

void setup() {
  Serial.begin(9600);
  pinMode(pumpPin, OUTPUT);
  digitalWrite(pumpPin, LOW);
}

void loop() {
  // Dummy sensor readings - replace with real readings
  float moisture = random(300, 700) / 10.0; // 30.0 - 70.0
  float temp = random(200, 350) / 10.0; // 20.0 - 35.0
  int light = random(40, 100);
  int airQ = random(50, 100);
  int metal = random(5, 40);

  Serial.print(moisture, 1);
  Serial.print(",");
  Serial.print(temp, 1);
  Serial.print(",");
  Serial.print(light);
  Serial.print(",");
  Serial.print(airQ);
  Serial.print(",");
  Serial.println(metal);

  // Listen for pump commands
  if (Serial.available()) {
    char c = Serial.read();
    if (c == 'W') {
      digitalWrite(pumpPin, HIGH);
    } else if (c == 'w') {
      digitalWrite(pumpPin, LOW);
    }
  }

  delay(2000);
}
