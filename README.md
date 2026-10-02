# SmartShield 🛡️
### Off-Grid Mesh Emergency SOS & Tactical Location System

SmartShield is a decentralized, off-grid emergency communication system built for environments where cellular networks and internet connectivity fail—such as natural disaster zones, remote wilderness expeditions, or blackout scenarios.

By combining low-power **Heltec WiFi LoRa 32 V3 (ESP32-S3)** hardware nodes with a **Flutter mobile app**, SmartShield creates a self-healing mesh network capable of broadcasting location data, peer-to-peer text messages, and high-priority emergency SOS alerts across kilometers without cellular towers or satellite subscriptions.

---

## 🌟 Key Features

- **🌐 Autonomous Off-Grid Mesh Networking**  
  Uses Semtech SX1262 LoRa transceivers operating in sub-GHz bands (433/868/915 MHz) with multi-hop packet forwarding and priority preemption.
- **🚨 Instant Emergency SOS Triggers**  
  - **Standard SOS**: Long-press activation with haptic vibration, OLED alerts, and mesh broadcast.
  - **Silent / Stealth SOS**: Triple-click activation for covert distress signaling without illuminating the screen or vibrating.
- **📍 Real-Time Location & GPS Fallback**  
  Equipped with u-blox NEO-6M GPS modules. If node GPS lock is lost, the system automatically falls back to smartphone GPS via BLE.
- **📱 Flutter Companion App**  
  Cross-platform mobile application featuring an offline radar map, directional compass, live mesh chat interface, and interactive alert management over Bluetooth LE (Nordic UART Service).
- **⚡ Smart Power Gating**  
  Utilizes the ESP32-S3 `VEXT` bus control to completely un-power peripherals during deep sleep, keeping standby power consumption under 25µA.
- **📄 Research & Patent Specification**  
  Includes complete IEEE research paper draft, system flowcharts, and patent specification documentation for academic or commercial submission.

---

## 🏗️ Hardware Architecture & Wiring

SmartShield nodes run on the **Heltec WiFi LoRa 32 (V3)** board powered by an ESP32-S3 dual-core microcontroller and SX1262 radio module.

### Core Components
1. **Node**: Heltec WiFi LoRa 32 (V3) (ESP32-S3, 8MB Flash)
2. **GPS Module**: u-blox NEO-6M with ceramic patch antenna
3. **Emergency Buttons**: Physical tactile push button (GPIO 4) & onboard PRG button (GPIO 0)
4. **Haptic Feedback**: 3V Coin / Cylindrical vibration motor driven via 2N2222 NPN transistor
5. **Display**: Onboard 0.96" Monochrome SSD1306 OLED (128x64)
6. **Battery**: 3.7V 1050mAh LiPo battery with TP4056 USB-C charging module

### Pinout Connections

| Component | Component Pin | Heltec V3 ESP32-S3 Pin | Notes |
| :--- | :--- | :--- | :--- |
| **NEO-6M GPS** | VCC | 3V3 / VEXT | Power supply (VEXT enables power gating) |
| | GND | GND | Ground |
| | TX | GPIO 47 | ESP32 Hardware RX |
| | RX | GPIO 48 | ESP32 Hardware TX |
| **Tactile Button** | Pin A | GPIO 4 | Input with internal pull-up (`INPUT_PULLUP`) |
| | Pin B | GND | Active-LOW trigger |
| **PRG Button** | Onboard | GPIO 0 | Built-in active-LOW user button |
| **Vibration Motor**| Base / Gate | GPIO 5 | Driven via 2N2222 transistor & 1k resistor |
| **OLED Display** | SDA / SCL | GPIO 17 / GPIO 18 | Internal I2C |
| **SX1262 LoRa** | NSS / SCK | GPIO 8 / GPIO 9 | Internal SPI bus |

---

## 📡 Wireless Mesh & BLE Communication

SmartShield operates on a custom binary frame protocol engineered for low bandwidth and minimal airtime.

```
+---------------+------------------+------------------+------------------+
| Magic (1B)    | Packet ID (2B)   | Sender ID (2B)   | Recipient ID (2B)|
| 0x53 ('S')    | 0x0001 - 0xFFFF  | Node ID          | 0xFFFF = Broadcast|
+---------------+------------------+------------------+------------------+
| Type (1B)     | Priority (1B)    | Hop Count (1B)   | Max Hops (1B)    |
| 0x01 - 0x07   | 0=Norm, 2=Emerg  | Dynamic TTL      | Default Max: 4   |
+---------------+------------------+------------------+------------------+
| GPS Source(1B)| Latitude (4B)    | Longitude (4B)   | Battery (1B)     |
| 0, 1, 2       | Fixed Scaled 1e7 | Fixed Scaled 1e7 | 0-100%           |
+---------------+------------------+------------------+------------------+
```

### Packet Types
- `0x01 CHAT`: Off-grid peer-to-peer text message.
- `0x02 SOS`: High-priority emergency beacon with mesh flooding.
- `0x03 POSITION`: Background location packet.
- `0x04 ACK`: Hop delivery confirmation.
- `0x07 SILENT SOS`: Discrete emergency alert (OLED off, no motor vibration).

---

## 📁 Repository Structure

```
SmartShield/
├── firmware/
│   └── Heltec_Mesh_SOS/           # ESP32-S3 Firmware (C++ / Arduino IDE)
│       ├── Heltec_Mesh_SOS.ino    # Main firmware loop & interrupt handlers
│       ├── RadioDriver.h          # SX1262 LoRa driver & mesh routing
│       ├── GpsManager.h           # TinyGPS++ interface & fallback
│       ├── BleBridge.h            # Nordic UART BLE interface
│       ├── DisplayManager.h       # SSD1306 UI renderer
│       └── HapticEngine.h         # Vibration patterns & alerts
├── mesh_sos_app/                  # Flutter Mobile App (Android / iOS)
│   ├── lib/                       # App state management, BLE sync & UI views
│   ├── assets/                    # Icons and map assets
│   └── pubspec.yaml               # Flutter dependencies
├── docs/                          # Project Documentation
│   ├── IEEE_RESEARCH_PAPER_AND_PATENT_SPECIFICATION.md
│   ├── PATENT_NOTES.md
│   ├── PROTOCOL.md                # Binary frame specification
│   ├── WIRING.md                  # Detailed hardware schematics
│   └── SmartShield_Final_Year_Project_Report.pdf
└── README.md
```

---

## 🛠️ Quick Start Guide

### 1. Flash Node Firmware
1. Install [Arduino IDE](https://www.arduino.cc/en/software) with the **ESP32 Board Manager** (`esp32 by Espressif Systems`).
2. Select Board: **Heltec WiFi LoRa 32(V3)**.
3. Install required libraries:
   - `RadioLib`
   - `TinyGPSPlus`
   - `Adafruit_SSD1306` & `Adafruit_GFX`
4. Open [`firmware/Heltec_Mesh_SOS/Heltec_Mesh_SOS.ino`](file:///Users/piyushlomte/Downloads/FinalYear/firmware/Heltec_Mesh_SOS/Heltec_Mesh_SOS.ino) and upload to your board.

### 2. Run Mobile Companion App
1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install).
2. Connect your mobile device via USB or start an emulator.
3. Navigate to the app directory and launch:
   ```bash
   cd mesh_sos_app
   flutter pub get
   flutter run
   ```

---

## 📜 License & Citation

Developed as a Final Year Engineering Project on decentralized emergency response.  
For research citation, hardware schematics, or patent inquiries, refer to the [`docs/`](file:///Users/piyushlomte/Downloads/FinalYear/docs/) directory.