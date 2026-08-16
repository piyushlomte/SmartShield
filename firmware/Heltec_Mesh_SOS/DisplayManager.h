#ifndef DISPLAY_MANAGER_H
#define DISPLAY_MANAGER_H

#include <Arduino.h>
#include <Wire.h>
#include "Config.h"
#include "MeshProtocol.h"

// Standard 5x7 Basic Font for lightweight direct rendering
extern const uint8_t font5x7[];

class DisplayManager {
private:
    uint8_t _i2cAddr = 0x3C;
    uint8_t _currentPage = 0;
    uint32_t _lastPageSwitch = 0;
    bool _isSosMode = false;
    bool _stealthMode = false;
    uint8_t _buffer[1024]; // 128x64 pixels (1 bit per pixel)

    void sendCommand(uint8_t cmd) {
        Wire.beginTransmission(_i2cAddr);
        Wire.write(0x00);
        Wire.write(cmd);
        Wire.endTransmission();
    }

    void drawChar(int x, int y, char c, bool inverted = false) {
        if (c < 32 || c > 126) c = '?';
        uint16_t fontOffset = (c - 32) * 5;
        for (int i = 0; i < 5; i++) {
            if (x + i >= 128 || x + i < 0) continue;
            uint8_t col = pgm_read_byte(&font5x7[fontOffset + i]);
            for (int j = 0; j < 8; j++) {
                int py = y + j;
                if (py >= 64 || py < 0) continue;
                bool pixelOn = (col & (1 << j)) != 0;
                if (inverted) pixelOn = !pixelOn;
                setPixel(x + i, py, pixelOn);
            }
        }
    }

public:
    DisplayManager() {}

    void begin() {
        // Power on Vext for Heltec V3
        pinMode(PIN_VEXT_CTRL, OUTPUT);
        digitalWrite(PIN_VEXT_CTRL, LOW); // LOW enables OLED and external sensors
        delay(50);

        // Reset OLED
        pinMode(PIN_OLED_RST, OUTPUT);
        digitalWrite(PIN_OLED_RST, LOW);
        delay(20);
        digitalWrite(PIN_OLED_RST, HIGH);
        delay(50);

        Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL, 400000);

        // Init SSD1306 128x64 Commands
        sendCommand(0xAE); // Display OFF
        sendCommand(0xD5); sendCommand(0x80); // Set Clock Divide Ratio
        sendCommand(0xA8); sendCommand(0x3F); // Set Multiplex (64 rows)
        sendCommand(0xD3); sendCommand(0x00); // Display Offset
        sendCommand(0x40); // Start Line 0
        sendCommand(0x8D); sendCommand(0x14); // Enable Charge Pump
        sendCommand(0x20); sendCommand(0x00); // Horizontal Addressing Mode
        sendCommand(0xA1); // Segment Remap
        sendCommand(0xC8); // COM Output Scan Direction
        sendCommand(0xDA); sendCommand(0x12); // COM Pins config
        sendCommand(0x81); sendCommand(0xCF); // Contrast
        sendCommand(0xD9); sendCommand(0xF1); // Pre-charge Period
        sendCommand(0xDB); sendCommand(0x40); // VCOMH Deselect Level
        sendCommand(0xA4); // Entire Display ON
        sendCommand(0xA6); // Normal Display
        sendCommand(0xAF); // Display ON

        clear();
        render();
    }

    void setPixel(int x, int y, bool color) {
        if (x < 0 || x >= 128 || y < 0 || y >= 64) return;
        uint16_t byteIdx = x + (y / 8) * 128;
        if (color) {
            _buffer[byteIdx] |= (1 << (y % 8));
        } else {
            _buffer[byteIdx] &= ~(1 << (y % 8));
        }
    }

    void clear() {
        memset(_buffer, 0x00, sizeof(_buffer));
    }

    void printString(int x, int y, const char *str, bool inverted = false) {
        int cursorX = x;
        while (*str) {
            drawChar(cursorX, y, *str, inverted);
            cursorX += 6;
            str++;
        }
    }

    void drawHeader(uint16_t nodeId, uint8_t batPercent, bool bleConnected) {
        // Top status bar
        char buf[32];
        snprintf(buf, sizeof(buf), "#%04X", nodeId);
        printString(2, 2, buf);

        snprintf(buf, sizeof(buf), "%s", bleConnected ? "BLE:ON" : "BLE:--");
        printString(50, 2, buf);

        snprintf(buf, sizeof(buf), "BAT:%d%%", batPercent);
        printString(88, 2, buf);

        // Separator line
        for (int x = 0; x < 128; x++) {
            setPixel(x, 11, true);
        }
    }

    void showStatusPage(uint16_t nodeId, uint8_t bat, bool ble, double lat, double lon, uint8_t sats, uint16_t relayedCount) {
        if (_stealthMode) return;
        clear();
        drawHeader(nodeId, bat, ble);

        char buf[32];
        snprintf(buf, sizeof(buf), "GPS Sats: %d", sats);
        printString(2, 16, buf);

        if (lat != 0.0 || lon != 0.0) {
            snprintf(buf, sizeof(buf), "Lat: %.4f", lat);
            printString(2, 27, buf);
            snprintf(buf, sizeof(buf), "Lon: %.4f", lon);
            printString(2, 38, buf);
        } else {
            printString(2, 27, "Acquiring GPS Fix...");
            printString(2, 38, "Phone BLE fallback ready");
        }

        snprintf(buf, sizeof(buf), "Packets Relayed: %d", relayedCount);
        printString(2, 50, buf);

        render();
    }

    void showSosAlert(uint16_t senderId, double lat, double lon, const char *distressMsg) {
        if (_stealthMode) return;
        clear();
        // Inverted top banner
        for (int y = 0; y < 14; y++) {
            for (int x = 0; x < 128; x++) setPixel(x, y, true);
        }
        printString(18, 3, "!!! EMERGENCY SOS !!!", true);

        char buf[32];
        snprintf(buf, sizeof(buf), "NODE: 0x%04X", senderId);
        printString(2, 18, buf);

        if (lat != 0.0 || lon != 0.0) {
            snprintf(buf, sizeof(buf), "%.5f, %.5f", lat, lon);
            printString(2, 30, buf);
        } else {
            printString(2, 30, "NO GPS COORDINATES");
        }

        if (distressMsg && strlen(distressMsg) > 0) {
            printString(2, 44, distressMsg);
        } else {
            printString(2, 44, "Assistance Requested!");
        }

        printString(2, 55, "Preemption active (P1)");
        render();
    }

    void showMessagePage(uint16_t senderId, const char *msg, int16_t rssi) {
        if (_stealthMode) return;
        clear();
        char buf[32];
        snprintf(buf, sizeof(buf), "FROM: #%04X  %ddBm", senderId, rssi);
        printString(2, 2, buf);
        for (int x = 0; x < 128; x++) setPixel(x, 11, true);

        // Render message wrapped
        int y = 16;
        int x = 2;
        while (*msg && y < 56) {
            drawChar(x, y, *msg);
            x += 6;
            if (x > 120) {
                x = 2;
                y += 10;
            }
            msg++;
        }
        render();
    }

    void showRescueResponsePage(uint16_t responderId, const char *responseMsg) {
        if (_stealthMode) return;
        clear();
        for (int y = 0; y < 14; y++) {
            for (int x = 0; x < 128; x++) setPixel(x, y, true);
        }
        printString(8, 3, "RESCUE EN ROUTE!", true);

        char buf[32];
        snprintf(buf, sizeof(buf), "FROM: Node 0x%04X", responderId);
        printString(2, 18, buf);

        if (responseMsg && strlen(responseMsg) > 0) {
            printString(2, 32, responseMsg);
        } else {
            printString(2, 32, "Help is on the way!");
        }

        printString(2, 50, "Stay at your location!");
        render();
    }

    void showSosCancelledPage(uint16_t senderId) {
        if (_stealthMode) return;
        clear();
        for (int y = 0; y < 14; y++) {
            for (int x = 0; x < 128; x++) setPixel(x, y, true);
        }
        printString(14, 3, "SOS RESOLVED/SAFE", true);

        char buf[32];
        snprintf(buf, sizeof(buf), "Node 0x%04X Cancelled", senderId);
        printString(2, 22, buf);
        printString(2, 40, "Emergency stand-down");
        render();
    }

    void setStealth(bool stealth) {
        _stealthMode = stealth;
        if (_stealthMode) {
            clear();
            render();
        }
    }

    void render() {
        sendCommand(0x21); sendCommand(0); sendCommand(127); // Col addr
        sendCommand(0x22); sendCommand(0); sendCommand(7);   // Page addr

        for (int i = 0; i < 1024; i += 16) {
            Wire.beginTransmission(_i2cAddr);
            Wire.write(0x40); // Data prefix
            for (int j = 0; j < 16; j++) {
                Wire.write(_buffer[i + j]);
            }
            Wire.endTransmission();
        }
    }

    void nextPage() {
        _currentPage = (_currentPage + 1) % 3;
    }

    uint8_t getPage() const { return _currentPage; }
};

// Basic 5x7 ASCII Character Font Table
const uint8_t font5x7[] PROGMEM = {
    0x00, 0x00, 0x00, 0x00, 0x00, // 32 ' '
    0x00, 0x00, 0x5F, 0x00, 0x00, // 33 '!'
    0x00, 0x07, 0x00, 0x07, 0x00, // 34 '"'
    0x14, 0x7F, 0x14, 0x7F, 0x14, // 35 '#'
    0x24, 0x2A, 0x7F, 0x2A, 0x12, // 36 '$'
    0x23, 0x13, 0x08, 0x64, 0x62, // 37 '%'
    0x36, 0x49, 0x55, 0x22, 0x50, // 38 '&'
    0x00, 0x05, 0x03, 0x00, 0x00, // 39 '''
    0x00, 0x1C, 0x22, 0x41, 0x00, // 40 '('
    0x00, 0x41, 0x22, 0x1C, 0x00, // 41 ')'
    0x14, 0x08, 0x3E, 0x08, 0x14, // 42 '*'
    0x08, 0x08, 0x3E, 0x08, 0x08, // 43 '+'
    0x00, 0x50, 0x30, 0x00, 0x00, // 44 ','
    0x08, 0x08, 0x08, 0x08, 0x08, // 45 '-'
    0x00, 0x60, 0x60, 0x00, 0x00, // 46 '.'
    0x20, 0x10, 0x08, 0x04, 0x02, // 47 '/'
    0x3E, 0x51, 0x49, 0x45, 0x3E, // 48 '0'
    0x00, 0x42, 0x7F, 0x40, 0x00, // 49 '1'
    0x42, 0x61, 0x51, 0x49, 0x46, // 50 '2'
    0x21, 0x41, 0x45, 0x4B, 0x31, // 51 '3'
    0x18, 0x14, 0x12, 0x7F, 0x10, // 52 '4'
    0x27, 0x45, 0x45, 0x45, 0x39, // 53 '5'
    0x3C, 0x4A, 0x49, 0x49, 0x30, // 54 '6'
    0x01, 0x71, 0x09, 0x05, 0x03, // 55 '7'
    0x36, 0x49, 0x49, 0x49, 0x36, // 56 '8'
    0x06, 0x49, 0x49, 0x29, 0x1E, // 57 '9'
    0x00, 0x36, 0x36, 0x00, 0x00, // 58 ':'
    0x00, 0x56, 0x36, 0x00, 0x00, // 59 ';'
    0x08, 0x14, 0x22, 0x41, 0x00, // 60 '<'
    0x14, 0x14, 0x14, 0x14, 0x14, // 61 '='
    0x00, 0x41, 0x22, 0x14, 0x08, // 62 '>'
    0x02, 0x01, 0x51, 0x09, 0x06, // 63 '?'
    0x32, 0x49, 0x79, 0x41, 0x3E, // 64 '@'
    0x7E, 0x11, 0x11, 0x11, 0x7E, // 65 'A'
    0x7F, 0x49, 0x49, 0x49, 0x36, // 66 'B'
    0x3E, 0x41, 0x41, 0x41, 0x22, // 67 'C'
    0x7F, 0x41, 0x41, 0x22, 0x1C, // 68 'D'
    0x7F, 0x49, 0x49, 0x49, 0x41, // 69 'E'
    0x7F, 0x09, 0x09, 0x09, 0x01, // 70 'F'
    0x3E, 0x41, 0x49, 0x49, 0x7A, // 71 'G'
    0x7F, 0x08, 0x08, 0x08, 0x7F, // 72 'H'
    0x00, 0x41, 0x7F, 0x41, 0x00, // 73 'I'
    0x20, 0x40, 0x41, 0x3F, 0x01, // 74 'J'
    0x7F, 0x08, 0x14, 0x22, 0x41, // 75 'K'
    0x7F, 0x40, 0x40, 0x40, 0x40, // 76 'L'
    0x7F, 0x02, 0x0C, 0x02, 0x7F, // 77 'M'
    0x7F, 0x04, 0x08, 0x10, 0x7F, // 78 'N'
    0x3E, 0x41, 0x41, 0x41, 0x3E, // 79 'O'
    0x7F, 0x09, 0x09, 0x09, 0x06, // 80 'P'
    0x3E, 0x41, 0x51, 0x21, 0x5E, // 81 'Q'
    0x7F, 0x09, 0x19, 0x29, 0x46, // 82 'R'
    0x46, 0x49, 0x49, 0x49, 0x31, // 83 'S'
    0x01, 0x01, 0x7F, 0x01, 0x01, // 84 'T'
    0x3F, 0x40, 0x40, 0x40, 0x3F, // 85 'U'
    0x1F, 0x20, 0x40, 0x20, 0x1F, // 86 'V'
    0x7F, 0x20, 0x18, 0x20, 0x7F, // 87 'W'
    0x63, 0x14, 0x08, 0x14, 0x63, // 88 'X'
    0x07, 0x08, 0x70, 0x08, 0x07, // 89 'Y'
    0x61, 0x51, 0x49, 0x45, 0x43, // 90 'Z'
    0x00, 0x7F, 0x41, 0x41, 0x00, // 91 '['
    0x02, 0x04, 0x08, 0x10, 0x20, // 92 '\'
    0x00, 0x41, 0x41, 0x7F, 0x00, // 93 ']'
    0x04, 0x02, 0x01, 0x02, 0x04, // 94 '^'
    0x40, 0x40, 0x40, 0x40, 0x40, // 95 '_'
    0x00, 0x01, 0x02, 0x04, 0x00, // 96 '`'
    0x20, 0x54, 0x54, 0x54, 0x78, // 97 'a'
    0x7F, 0x48, 0x44, 0x44, 0x38, // 98 'b'
    0x38, 0x44, 0x44, 0x44, 0x20, // 99 'c'
    0x38, 0x44, 0x44, 0x48, 0x7F, // 100 'd'
    0x38, 0x54, 0x54, 0x54, 0x18, // 101 'e'
    0x08, 0x7E, 0x09, 0x01, 0x02, // 102 'f'
    0x0C, 0x52, 0x52, 0x52, 0x3E, // 103 'g'
    0x7F, 0x08, 0x04, 0x04, 0x78, // 104 'h'
    0x00, 0x44, 0x7D, 0x40, 0x00, // 105 'i'
    0x20, 0x40, 0x44, 0x3D, 0x00, // 106 'j'
    0x7F, 0x10, 0x28, 0x44, 0x00, // 107 'k'
    0x00, 0x41, 0x7F, 0x40, 0x00, // 108 'l'
    0x7C, 0x04, 0x18, 0x04, 0x78, // 109 'm'
    0x7C, 0x08, 0x04, 0x04, 0x78, // 110 'n'
    0x38, 0x44, 0x44, 0x44, 0x38, // 111 'o'
    0x7C, 0x14, 0x14, 0x14, 0x08, // 112 'p'
    0x08, 0x14, 0x14, 0x18, 0x7C, // 113 'q'
    0x7C, 0x08, 0x04, 0x04, 0x08, // 114 'r'
    0x48, 0x54, 0x54, 0x54, 0x20, // 115 's'
    0x04, 0x3F, 0x44, 0x40, 0x20, // 116 't'
    0x3C, 0x40, 0x40, 0x20, 0x7C, // 117 'u'
    0x1C, 0x20, 0x40, 0x20, 0x1C, // 118 'v'
    0x3C, 0x40, 0x30, 0x40, 0x3C, // 119 'w'
    0x44, 0x28, 0x10, 0x28, 0x44, // 120 'x'
    0x0C, 0x50, 0x50, 0x50, 0x3C, // 121 'y'
    0x44, 0x64, 0x54, 0x4C, 0x44, // 122 'z'
    0x00, 0x08, 0x36, 0x41, 0x00, // 123 '{'
    0x00, 0x00, 0x7F, 0x00, 0x00, // 124 '|'
    0x00, 0x41, 0x36, 0x08, 0x00, // 125 '}'
    0x08, 0x08, 0x2A, 0x1C, 0x08  // 126 '~'
};

#endif // DISPLAY_MANAGER_H
