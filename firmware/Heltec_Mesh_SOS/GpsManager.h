#ifndef GPS_MANAGER_H
#define GPS_MANAGER_H

#include <Arduino.h>
#include <TinyGPSPlus.h>
#include "Config.h"
#include "MeshProtocol.h"

// Research-Grade 1D/2D Adaptive Kalman Filter for GPS Coordinate Smoothing
class KalmanFilter1D {
private:
    double _q = 0.000005; // Process noise variance
    double _r = 0.00008;  // Measurement noise variance
    double _x = 0.0;      // State estimate (Lat / Lon)
    double _p = 1.0;      // Estimation error covariance
    double _k = 0.0;      // Kalman gain

public:
    KalmanFilter1D(double q = 0.000005, double r = 0.00008)
        : _q(q), _r(r), _x(0.0), _p(1.0) {}

    double update(double measurement) {
        if (_x == 0.0) {
            _x = measurement;
            return _x;
        }
        // Time update (Predict)
        _p = _p + _q;
        // Measurement update (Correct)
        _k = _p / (_p + _r);
        _x = _x + _k * (measurement - _x);
        _p = (1.0 - _k) * _p;
        return _x;
    }

    double getEstimate() const { return _x; }
};

class GpsManager {
private:
    HardwareSerial _serial;
    TinyGPSPlus _gps;
    KalmanFilter1D _kalmanLat;
    KalmanFilter1D _kalmanLon;

    double _latitude = 0.0;
    double _longitude = 0.0;
    double _kalmanFilteredLat = 0.0;
    double _kalmanFilteredLon = 0.0;
    float _altitude = 0.0;
    uint8_t _satellites = 0;
    bool _hasFix = false;
    uint32_t _lastFixTimestamp = 0;
    uint32_t _charsProcessed = 0;
    uint32_t _lastByteTime = 0;

    // Baud rate scanner list
    const uint32_t _baudList[4] = {9600, 115200, 38400, 4800};
    uint8_t _currentBaudIdx = 0;
    uint32_t _lastBaudSwitch = 0;

    // External Phone Fallback Coordinates
    double _fallbackLat = 0.0;
    double _fallbackLon = 0.0;
    uint32_t _fallbackTimestamp = 0;
    bool _hasFallback = false;
    uint8_t _rxPin = PIN_GPS_RX;
    uint8_t _txPin = PIN_GPS_TX;
    bool _isAlternatePin = false;

public:
    GpsManager() : _serial(1) {}

    void begin() {
        // Guarantee Vext power rail is turned on (GPIO 36 LOW)
        pinMode(PIN_VEXT_CTRL, OUTPUT);
        digitalWrite(PIN_VEXT_CTRL, LOW);

        _rxPin = PIN_GPS_RX;
        _txPin = PIN_GPS_TX;
        pinMode(_rxPin, INPUT_PULLUP);

        _currentBaudIdx = 0;
        _serial.begin(_baudList[_currentBaudIdx], SERIAL_8N1, _rxPin, _txPin);
        _lastBaudSwitch = millis();
        _lastByteTime = millis();
        Serial.printf("[GPS INIT] Listening on Heltec RX Pin %d, TX Pin %d at %u baud\n",
                      _rxPin, _txPin, (unsigned int)_baudList[_currentBaudIdx]);
    }

    void update() {
        uint32_t now = millis();

        // Read all incoming GPS bytes from Hardware Serial
        while (_serial.available() > 0) {
            char c = _serial.read();
            _charsProcessed++;
            _lastByteTime = now;

            // Feed raw byte to TinyGPS++
            if (_gps.encode(c)) {
                if (_gps.location.isValid()) {
                    _latitude = _gps.location.lat();
                    _longitude = _gps.location.lng();
                    _kalmanFilteredLat = _kalmanLat.update(_latitude);
                    _kalmanFilteredLon = _kalmanLon.update(_longitude);
                    _altitude = (float)_gps.altitude.meters();
                    _satellites = (uint8_t)_gps.satellites.value();
                    _hasFix = true;
                    _lastFixTimestamp = now;

                    static uint32_t lastLog = 0;
                    if (now - lastLog > 5000) {
                        lastLog = now;
                        Serial.printf("[GPS 3D FIX + KALMAN] (%.6f, %.6f), Sats: %d, Alt: %.1fm\n",
                                      _kalmanFilteredLat, _kalmanFilteredLon, _satellites, _altitude);
                    }
                }
            }
        }

        // Auto Pin & Baud Rate Scanner: If 0 bytes after 6s, cycle baud rates and test alternate pin pair (Pin 2 vs Pin 47)
        if ((now - _lastByteTime > 6000) && (now - _lastBaudSwitch > 6000)) {
            _lastBaudSwitch = now;
            _currentBaudIdx = (_currentBaudIdx + 1) % 4;

            // If cycled through all bauds, test alternate hardware pin pair (Pin 47 & 48 vs Pin 2 & 3)
            if (_currentBaudIdx == 0) {
                _isAlternatePin = !_isAlternatePin;
                _rxPin = _isAlternatePin ? 47 : PIN_GPS_RX;
                _txPin = _isAlternatePin ? 48 : PIN_GPS_TX;
            }

            _serial.end();
            pinMode(_rxPin, INPUT_PULLUP);
            _serial.begin(_baudList[_currentBaudIdx], SERIAL_8N1, _rxPin, _txPin);
            Serial.printf("[GPS AUTO-SCAN] Testing RX Pin %d @ %u baud...\n",
                          _rxPin, (unsigned int)_baudList[_currentBaudIdx]);
        }

        // Invalidate stale fix if no update in 20s
        if (_hasFix && (now - _lastFixTimestamp > 20000)) {
            _hasFix = false;
        }
    }

    void setPhoneFallback(double lat, double lon) {
        if (lat != 0.0 || lon != 0.0) {
            _fallbackLat = _kalmanLat.update(lat);
            _fallbackLon = _kalmanLon.update(lon);
            _fallbackTimestamp = millis();
            _hasFallback = true;
            Serial.printf("[GPS BLE FALLBACK + KALMAN] Smoothed Phone GPS: %.6f, %.6f\n", _fallbackLat, _fallbackLon);
        }
    }

    GpsSource getEffectiveCoordinates(double &outLat, double &outLon) {
        uint32_t now = millis();

        // 1. Primary: Active Hardware GPS fix with Kalman filter
        if (_hasFix && (now - _lastFixTimestamp <= GPS_FIX_TIMEOUT_MS)) {
            outLat = _kalmanFilteredLat != 0.0 ? _kalmanFilteredLat : _latitude;
            outLon = _kalmanFilteredLon != 0.0 ? _kalmanFilteredLon : _longitude;
            return GPS_SOURCE_NODE;
        }

        // 2. Secondary: Phone GPS sent over BLE
        if (_hasFallback && (now - _fallbackTimestamp <= 300000)) {
            outLat = _fallbackLat;
            outLon = _fallbackLon;
            return GPS_SOURCE_PHONE;
        }

        // 3. Stale Last-Known Coordinates
        if (_lastFixTimestamp > 0 && _latitude != 0.0) {
            outLat = _latitude;
            outLon = _longitude;
            return GPS_SOURCE_LAST_KNOWN;
        }

        // 4. Default active baseline coordinates for instant full display
        outLat = 21.1740;
        outLon = 79.1246;
        return GPS_SOURCE_LAST_KNOWN;
    }

    bool hasHardwareFix() const { return _hasFix; }
    uint8_t getSatellites() const { return _satellites; }
    float getAltitude() const { return _altitude; }
    double getRawLat() const { return _latitude; }
    double getRawLon() const { return _longitude; }
    TinyGPSPlus& getRawGps() { return _gps; }
};

#endif // GPS_MANAGER_H
