# Hardware Wiring & Schematic Guide

## System Components
1. **Microcontroller & LoRa Node**: Heltec WiFi LoRa 32 (V3) (2 Units for Dual-Device Mesh)
   - SoC: ESP32-S3FN8 (Dual-Core 240MHz, 8MB Flash)
   - LoRa Transceiver: Semtech SX1262 (433–510MHz / 863–928MHz)
   - Onboard Display: 0.96-inch Monochrome OLED (SSD1306, 128×64)
   - Onboard Button: PRG / User button connected to **GPIO 0** (Active-LOW)
2. **GPS Module**: u-blox NEO-6M (with ceramic patch antenna)
3. **Emergency Input (Choose One or Both)**:
   - **Tactile Push Button Switch** (Momentary NO switch between GPIO 4 and GND with internal pull-up)
   - **TTP223 Capacitive Touch Module** (Active HIGH)
   - **Built-in PRG Button** (GPIO 0, no extra wiring needed!)
4. **Vibration Motor**: 3V Coin / Cylindrical Coreless Haptic Motor + 2N2222/SS8050 NPN Driver or MOSFET
5. **Power Subsystem**: 3.7V 1050mAh LiPo Battery + TP4056 USB-C Charger with BMS

---

## Complete Pin Connection Table

| Peripheral | Peripheral Pin | Heltec V3 ESP32-S3 Pin | Mode / Notes |
| :--- | :--- | :--- | :--- |
| **NEO-6M GPS** | VCC | 3V3 (or VEXT) | 3.3V power supply |
| | GND | GND | Common ground |
| | TX | GPIO 47 | Hardware Serial RX |
| | RX | GPIO 48 | Hardware Serial TX |
| **Tactile Push Button** | Terminal A | GPIO 4 | Input with Internal Pull-Up (`INPUT_PULLUP`) |
| *(Option A - Recommended)* | Terminal B | GND | Active-LOW: pressing connects GPIO 4 to GND |
| **TTP223 Touch** | VCC | 3V3 | Power |
| *(Option B)* | GND | GND | Ground |
| | I/O (SIG) | GPIO 4 | Active-HIGH digital input (`BUTTON_ACTIVE_HIGH = true`) |
| **Onboard PRG Button** | Built-in | GPIO 0 | Built-in Active-LOW user button (works automatically) |
| **Vibration Motor** | VCC | 3V3 (or 5V for transistor collector) | Motor positive terminal |
| | Motor Base / Gate | GPIO 5 | Driven via transistor with 1k resistor + flyback diode |
| | GND | GND | Ground |
| **OLED (Onboard)** | SDA | GPIO 17 | I2C Data |
| | SCL | GPIO 18 | I2C Clock |
| | RST | GPIO 21 | OLED Reset |
| | VEXT Control | GPIO 36 | Active LOW (powers OLED & external sensors) |
| **SX1262 (Onboard)** | NSS | GPIO 8 | SPI Chip Select |
| | SCK | GPIO 9 | SPI Clock |
| | MOSI | GPIO 10 | SPI Data In |
| | MISO | GPIO 11 | SPI Data Out |
| | RST | GPIO 12 | Radio Reset |
| | BUSY | GPIO 13 | Radio Busy Flag |
| | DIO1 | GPIO 14 | Radio Interrupt Pin |
| **Battery Monitor** | ADC | GPIO 1 | Onboard voltage divider |
| | VBAT Ctrl | GPIO 37 | Active LOW (enables divider circuit) |

---

## Push Button Wiring Circuit (Tactile Switch)

Connect a standard 2-pin or 4-pin momentary tactile push button directly between **GPIO 4** and **GND**:

```
      Heltec V3 ESP32-S3
      +------------------+
      |                  |
      |           GPIO 4 |----------------+
      |                  |                |
      |                  |           [ Push Button ]
      |                  |                |
      |              GND |----------------+
      +------------------+
```

### Button Behavior & Gestures:
- **Single Short Press (< 800ms)**: Cycles OLED display pages (Status -> GPS -> Message history).
- **Long Press (Hold for 3 seconds)**: **TRIGGERS EMERGENCY SOS**.
  - Fetches current GPS latitude & longitude.
  - Transmits high-priority LoRa packet across mesh to all neighboring Heltec nodes.
  - Vibrates haptic motor and displays SOS alert on OLED.
  - Syncs alert with paired phone app over BLE.
- **Triple Click (3 quick taps within 1.5s)**: **TRIGGERS STEALTH / SILENT SOS**.
  - Transmits emergency beacon with GPS coordinates without lighting screen or vibrating motor (for hostage / discrete distress situations).

---

## Two Heltec Devices Communication (Dual-User SOS Mesh)

```
+----------------------------------------------------+          +----------------------------------------------------+
|               HELTEC NODE A (User 1)               |          |               HELTEC NODE B (User 2)               |
|                                                    |          |                                                    |
|  [Push Button (GPIO 4 / GPIO 0)]                   |          |  [SSD1306 OLED Display]                            |
|          | (Long Press 3s)                         |          |    - Alert: "!!! EMERGENCY SOS !!!"                |
|          v                                         |          |    - Node ID: 0x1A2B (User 1)                      |
|  [NEO-6M GPS Manager]                              |          |    - Lat: 18.52043, Lon: 73.85674                  |
|    - Reads Lat/Lon Coordinates                     |          |    - Distance & Bearing                            |
|          |                                         |          |                                                    |
|          v                                         |  SX1262  |  [Haptic Engine]                                   |
|  [SX1262 LoRa Radio TX] --------------------------->  LoRa  --->   - Plays SOS pattern vibration                   |
|    - Packet: Type=SOS, Priority=EMERGENCY          |   Mesh   |                                                    |
|    - Payload: Lat, Lon, Node ID, Battery           |          |  [BLE UART Bridge]                                 |
|                                                    |          |          | (Forward alert JSON)                    |
+----------------------------------------------------+          +----------|-----------------------------------------+
                                                                           v
                                                                +---------------------+
                                                                | Smartphone App      |
                                                                | (SmartShield App)   |
                                                                | - Pop-up SOS Banner |
                                                                | - Live Radar Pin    |
                                                                | - Direction compass |
                                                                +---------------------+
```

---

## Vibration Motor Driver Circuit

```
                      +3.3V / +5V
                           |
                        [Motor]
                           |----+
                           |    |  (1N4148 / 1N4007 Diode
                           |   [D]  Flyback protection)
                           |----+
                           |
                 1k     | /  (Collector)
   GPIO 5 -----[===]----|    2N2222 NPN Transistor
                        | \  (Emitter)
                           |
                          GND
```

---

## Power Management Best Practices
1. **VEXT Bus Usage**: Powering the NEO-6M GPS from the `VEXT` pin allows the ESP32-S3 firmware to completely shut off power to the GPS via `GPIO 36` during sleep mode, reducing standby current to under 25µA.
2. **Antenna Warning**: **NEVER** transmit or boot the Heltec LoRa32 board without an antenna attached to the IPEX / U.FL or SMA connector. Doing so will permanently burn out the SX1262 Power Amplifier.
