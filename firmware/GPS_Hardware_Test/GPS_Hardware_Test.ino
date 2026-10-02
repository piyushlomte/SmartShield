/*
 * =============================================================================
 * HELTEC WIFI LORA 32 (V3) - DIRECT GPS DIAGNOSTIC TEST
 * =============================================================================
 * Wiring:
 *   NEO-6M TX  ->  Heltec Pin 47
 *   NEO-6M RX  ->  Heltec Pin 48
 *   NEO-6M VCC ->  Heltec 3.3V (or 5V when USB connected)
 *   NEO-6M GND ->  Heltec GND
 * =============================================================================
 */

#include <Arduino.h>
#include <TinyGPSPlus.h>

#define PIN_GPS_RX    47
#define PIN_GPS_TX    48
#define PIN_VEXT_CTRL 36

HardwareSerial SerialGPS(1);
TinyGPSPlus gps;

void setup() {
  Serial.begin(115200);
  delay(1500);

  // Turn ON Vext power rail
  pinMode(PIN_VEXT_CTRL, OUTPUT);
  digitalWrite(PIN_VEXT_CTRL, LOW);

  // Start Hardware Serial on Pins 47 & 48
  SerialGPS.begin(9600, SERIAL_8N1, PIN_GPS_RX, PIN_GPS_TX);

  Serial.println("\n==========================================");
  Serial.println("   HELTEC V3 - NEO-6M GPS TEST BENCH      ");
  Serial.println("==========================================");
  Serial.printf("Listening on GPIO %d (RX) & GPIO %d (TX)...\n", PIN_GPS_RX, PIN_GPS_TX);
}

void loop() {
  while (SerialGPS.available() > 0) {
    char c = SerialGPS.read();
    
    // Print raw NMEA characters directly to Serial Monitor
    Serial.write(c);

    // Decode with TinyGPS++
    if (gps.encode(c)) {
      if (gps.location.isValid()) {
        Serial.println("\n------------------------------------------");
        Serial.printf(">>> 📍 LATITUDE:  %.6f\n", gps.location.lat());
        Serial.printf(">>> 📍 LONGITUDE: %.6f\n", gps.location.lng());
        Serial.printf(">>> 🛰️ SATELLITES: %d\n", gps.satellites.value());
        Serial.printf(">>> 🏔️ ALTITUDE:   %.1f meters\n", gps.altitude.meters());
        Serial.println("------------------------------------------");
      }
    }
  }

  // Diagnostic timeout warning
  if (millis() > 6000 && gps.charsProcessed() < 10) {
    static uint32_t lastWarn = 0;
    if (millis() - lastWarn > 5000) {
      lastWarn = millis();
      Serial.println("\n[!] NO BYTES RECEIVED YET.");
      Serial.println("    Check 1: NEO-6M TX wire -> Heltec Pin 47");
      Serial.println("    Check 2: NEO-6M GND wire -> Heltec GND");
      Serial.println("    Check 3: NEO-6M VCC wire -> Heltec 3.3V or 5V (Power LED ON?)");
    }
  }
}
