# Hardware Wiring & Schematic Guide

## System Components
1. **Microcontroller & LoRa Node**: Heltec WiFi LoRa 32 (V3)
   - SoC: ESP32-S3FN8 (Dual-Core 240MHz, 8MB Flash)
   - LoRa Transceiver: Semtech SX1262 (433–510MHz / 863–928MHz)
   - Onboard Display: 0.96-inch Monochrome OLED (SSD1306, 128×64)
2. **GPS Module**: u-blox NEO-6M (with ceramic patch antenna)
3. **Touch Sensor**: TTP223 Capacitive Touch Module
4. **Vibration Motor**: 3V Coin / Cylindrical Coreless Haptic Motor + 2N2222/SS8050 NPN Driver or MOSFET
5. **Power Subsystem**: 3.7V 1050mAh LiPo Battery + TP4056 USB-C Charger with BMS

---

## Complete Pin Connection Table

| Peripheral | Peripheral Pin | Heltec V3 ESP32-S3 Pin | Notes |
| :--- | :--- | :--- | :--- |
| **NEO-6M GPS** | VCC | 3V3 (or VEXT) | 3.3V power supply |
| | GND | GND | Common ground |
| | TX | GPIO 47 | Hardware Serial RX |
| | RX | GPIO 48 | Hardware Serial TX |
| **TTP223 Touch** | VCC | 3V3 | Power |
| | GND | GND | Ground |
| | I/O (SIG) | GPIO 4 | Active HIGH digital input |
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
