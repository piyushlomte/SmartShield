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
        analogReadResolution(12);    // 12-bit ADC
        update();
    }

    void update() {
        uint32_t now = millis();
        if (now - _lastSampleTime < 3000 && _lastSampleTime != 0) {
            return;
        }
        _lastSampleTime = now;

        digitalWrite(_ctrlPin, LOW); // Enable measurement divider
        delayMicroseconds(100);

        uint32_t rawSum = 0;
        for (int i = 0; i < 16; i++) {
            rawSum += analogReadMilliVolts(_adcPin);
        }
        float pinVoltage = (rawSum / 16.0f) / 1000.0f; // In Volts (calibrated by ESP32-S3 eFuse)

        // Heltec V3 Hardware Divider: 390k + 100k -> Ratio = 4.90
        _voltage = pinVoltage * 4.90f;

        // If running on USB cable without LiPo battery attached, pinVoltage is ~0V
        if (_voltage < 2.50f) {
            _percentage = 100; // USB / External 5V Powered
        } else if (_voltage >= 4.20f) {
            _percentage = 100;
        } else if (_voltage >= 4.05f) {
            _percentage = (uint8_t)(90 + ((_voltage - 4.05f) / 0.15f) * 10);
        } else if (_voltage >= 3.85f) {
            _percentage = (uint8_t)(60 + ((_voltage - 3.85f) / 0.20f) * 30);
        } else if (_voltage >= 3.70f) {
            _percentage = (uint8_t)(30 + ((_voltage - 3.70f) / 0.15f) * 30);
        } else if (_voltage >= 3.50f) {
            _percentage = (uint8_t)(10 + ((_voltage - 3.50f) / 0.20f) * 20);
        } else if (_voltage > 3.20f) {
            _percentage = (uint8_t)(((_voltage - 3.20f) / 0.30f) * 10);
        } else {
            _percentage = 5;
        }
    }

    float getVoltage() const { return _voltage; }
    uint8_t getPercentage() const { return _percentage; }
    bool isCritical() const { return _percentage < 15; }
};

#endif // BATTERY_MONITOR_H
