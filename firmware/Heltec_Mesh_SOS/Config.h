#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// =============================================================================
// HELTEC WIFI LORA 32 (V3) PIN DEFINITIONS (ESP32-S3FN8 + SX1262)
// =============================================================================
#define PIN_LORA_NSS        8
#define PIN_LORA_SCK        9
#define PIN_LORA_MOSI       10
#define PIN_LORA_MISO       11
#define PIN_LORA_RST        12
#define PIN_LORA_BUSY       13
#define PIN_LORA_DIO1       14

// OLED 0.96" I2C Pins (SSD1306)
#define PIN_OLED_SDA        17
#define PIN_OLED_SCL        18
#define PIN_OLED_RST        21
#define PIN_VEXT_CTRL       36    // LOW = Active (Powers on OLED & external sensors)

// External Peripherals Pinout
#define PIN_GPS_RX          2    // Connect to NEO-6M GPS TX
#define PIN_GPS_TX          3   // Connect to NEO-6M GPS RX
#define PIN_BUTTON_SOS      4     // Connect to Push Button or TTP223 (I/O)
#define BUTTON_ACTIVE_HIGH  false // Set false for standard tactile push button (GPIO to GND with INPUT_PULLUP), true for TTP223 Active-HIGH
#define PIN_ONBOARD_BUTTON  0     // Onboard PRG button on Heltec V3 (GPIO 0, Active-LOW)
#define PIN_VIBRATION_MOTOR 255   // Set 255 if testing/no motor (prevents brownout), or 5 if using MOSFET/transistor driver
#define PIN_BATTERY_ADC     1     // Built-in Heltec ADC voltage divider
#define PIN_VBAT_CTRL       37    // Set LOW to enable battery measurement divider

// =============================================================================
// RADIO CONFIGURATION (For 863-928MHz Heltec V3 Hardware Variant)
// =============================================================================
// Regional frequency for 863-928MHz hardware:
// 865.200 for India (865-867MHz license-free ISM band)
// 868.125 for Europe (868MHz band)
// 915.000 for US/Americas (902-928MHz band)
#define DEFAULT_LORA_FREQ       865.200   // In MHz (865.200 for India 865-867MHz band)
#define LORA_BANDWIDTH          125.0     // In kHz (125.0, 250.0, 500.0)
#define LORA_SPREADING_FACTOR   10        // SF7 to SF12 (SF10 offers great range/speed balance)
#define LORA_CODING_RATE        7         // 4/7 coding rate for high noise resilience
#define LORA_SYNC_WORD          0x34      // Mesh sync word (0x34 for private mesh)
#define LORA_OUTPUT_POWER       22        // Max SX1262 output: 22 dBm (~160mW)
#define LORA_PREAMBLE_LENGTH    12        // Standard preamble symbols

// =============================================================================
// MESH ROUTING & QUEUE CONSTANTS
// =============================================================================
#define MAX_HOP_COUNT           4         // Max retransmission hops across mesh
#define DEDUPLICATION_CACHE_SIZE 64       // Remember last N packet IDs to prevent loops
#define TX_QUEUE_SIZE_NORMAL    16        // Standard message queue length
#define TX_QUEUE_SIZE_SOS       8         // Dedicated high-priority emergency queue length
#define BROADCAST_NODE_ID       0xFFFF    // Destination ID for all-mesh broadcast
#define STORE_FORWARD_EXPIRY_MS 300000    // 5 minutes packet time-to-live in mesh cache

// =============================================================================
// EMERGENCY SOS & GESTURE PARAMETERS
// =============================================================================
#define TOUCH_LONG_PRESS_MS     3000      // 3.0 seconds continuous touch triggers SOS
#define TOUCH_TRIPLE_TAP_WINDOW 1500      // 3 quick taps within 1.5s triggers Silent SOS
#define SOS_BEACON_INTERVAL_MS  15000     // Repeat SOS beacon every 15 seconds
#define NORMAL_BEACON_INT_MS    20000     // Normal telemetry position beacon (20 seconds for fast auto-discovery)
#define GPS_FIX_TIMEOUT_MS      20000     // 20s timeout before engaging Phone BLE GPS fallback

// =============================================================================
// BLE SERVICE & CHARACTERISTIC UUIDs
// =============================================================================
#define BLE_DEVICE_NAME         "Heltec-Mesh-SOS"
#define SERVICE_UUID            "6E400001-B5A3-F393-E0A9-E50E24DCCA9E" // Nordic UART Service
#define CHAR_RX_UUID            "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" // Phone -> Node (Write)
#define CHAR_TX_UUID            "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" // Node -> Phone (Notify)

#endif // CONFIG_H
