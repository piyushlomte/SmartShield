#ifndef BATTERY_MONITOR_H
#define BATTERY_MONITOR_H

#include <Arduino.h>
#include "Config.h"

class BatteryMonitor {
private:
    uint8_t _adcPin;
    uint8_t _ctrlPin;
    float _voltage = 4.20f;
    uint8_t _percentage = 100;
    uint32_t _lastSampleTime = 0;

public:
    BatteryMonitor(uint8_t adcPin, uint8_t ctrlPin) : _adcPin(adcPin), _ctrlPin(ctrlPin) {}

    void begin() {
        pinMode(_ctrlPin, OUTPUT);
        digitalWrite(_ctrlPin, LOW); // LOW enables the divider on Heltec V3
        analogReadResolution(12);    // 12-bit ADC (0-4095)
        update();
    }

    void update() {
        uint32_t now = millis();
        if (now - _lastSampleTime < 5000 && _lastSampleTime != 0) {
            return;
        }
        _lastSampleTime = now;

        digitalWrite(_ctrlPin, LOW); // Enable measurement
        delayMicroseconds(50);

        uint32_t raw = 0;
        for (int i = 0; i < 16; i++) {
            raw += analogRead(_adcPin);
        }
        raw /= 16;

        // Heltec V3 voltage divider calibration factor:
        // Divider ratio = (390k + 100k) / 100k = 4.9
        // ADC reference is ~3.3V with 12-bit range (4095)
        float pinVoltage = (raw / 4095.0f) * 3.3f;
        _voltage = pinVoltage * 4.9f;

        // LiPo curve approximation (3.20V to 4.20V)
        if (_voltage >= 4.20f) {
            _percentage = 100;
        } else if (_voltage <= 3.30f) {
            _percentage = 0;
        } else {
            _percentage = (uint8_t)(((_voltage - 3.30f) / (4.20f - 3.30f)) * 100.0f);
        }
    }

    float getVoltage() const { return _voltage; }
    uint8_t getPercentage() const { return _percentage; }
    bool isCritical() const { return _percentage < 15; }
};

#endif // BATTERY_MONITOR_H
