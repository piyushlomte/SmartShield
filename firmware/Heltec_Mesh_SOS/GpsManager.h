#ifndef GPS_MANAGER_H
#define GPS_MANAGER_H

#include <Arduino.h>
#include "Config.h"
#include "MeshProtocol.h"

// Lightweight NMEA Parser to eliminate large library dependencies if needed
class GpsManager {
private:
    HardwareSerial _serial;
    double _latitude = 0.0;
    double _longitude = 0.0;
    float _altitude = 0.0;
    uint8_t _satellites = 0;
    bool _hasFix = false;
    uint32_t _lastFixTimestamp = 0;

    // External Phone Fallback Coordinates
    double _fallbackLat = 0.0;
    double _fallbackLon = 0.0;
    uint32_t _fallbackTimestamp = 0;
    bool _hasFallback = false;

    // Buffer for NMEA sentences
    char _nmeaBuffer[120];
    uint8_t _nmeaIndex = 0;

    void parseNmeaSentence(const char *nmea) {
        // Parse $GPGGA or $GNRMC
        if (strncmp(nmea, "$GPGGA", 6) == 0 || strncmp(nmea, "$GNGGA", 6) == 0) {
            char sentence[120];
            strncpy(sentence, nmea, sizeof(sentence));
            sentence[sizeof(sentence) - 1] = '\0';

            char *tokens[15];
            char *p = strtok(sentence, ",");
            int idx = 0;
            while (p != NULL && idx < 15) {
                tokens[idx++] = p;
                p = strtok(NULL, ",");
            }

            if (idx >= 10) {
                int fixQuality = atoi(tokens[6]);
                if (fixQuality > 0 && strlen(tokens[2]) > 0 && strlen(tokens[4]) > 0) {
                    double rawLat = atof(tokens[2]);
                    char latHem = tokens[3][0];
                    double rawLon = atof(tokens[4]);
                    char lonHem = tokens[5][0];

                    int latDeg = (int)(rawLat / 100);
                    double latMin = rawLat - (latDeg * 100);
                    _latitude = latDeg + (latMin / 60.0);
                    if (latHem == 'S') _latitude = -_latitude;

                    int lonDeg = (int)(rawLon / 100);
                    double lonMin = rawLon - (lonDeg * 100);
                    _longitude = lonDeg + (lonMin / 60.0);
                    if (lonHem == 'W') _longitude = -_longitude;

                    _satellites = (uint8_t)atoi(tokens[7]);
                    _altitude = (float)atof(tokens[9]);
                    _hasFix = true;
                    _lastFixTimestamp = millis();
                } else {
                    _hasFix = false;
                }
            }
        }
    }

public:
    GpsManager() : _serial(1) {}

    void begin() {
        _serial.begin(9600, SERIAL_8N1, PIN_GPS_RX, PIN_GPS_TX);
    }

    void update() {
        while (_serial.available()) {
            char c = _serial.read();
            if (c == '$') {
                _nmeaIndex = 0;
                _nmeaBuffer[_nmeaIndex++] = c;
            } else if (_nmeaIndex > 0 && _nmeaIndex < sizeof(_nmeaBuffer) - 1) {
                if (c == '\r' || c == '\n') {
                    _nmeaBuffer[_nmeaIndex] = '\0';
                    parseNmeaSentence(_nmeaBuffer);
                    _nmeaIndex = 0;
                } else {
                    _nmeaBuffer[_nmeaIndex++] = c;
                }
            }
        }

        // Fix timeout check (stale if no NMEA fix in last 15s)
        if (_hasFix && (millis() - _lastFixTimestamp > 15000)) {
            _hasFix = false;
        }
    }

    // Set phone location fallback injected via BLE
    void setPhoneFallback(double lat, double lon) {
        _fallbackLat = lat;
        _fallbackLon = lon;
        _fallbackTimestamp = millis();
        _hasFallback = true;
    }

    // Dual-source location arbitration: Live Node -> Phone BLE Fallback -> Last Known
    GpsSource getEffectiveCoordinates(double &outLat, double &outLon) {
        uint32_t now = millis();

        // 1. Primary Source: Hardware GPS fix
        if (_hasFix && (now - _lastFixTimestamp <= GPS_FIX_TIMEOUT_MS)) {
            outLat = _latitude;
            outLon = _longitude;
            return GPS_SOURCE_NODE;
        }

        // 2. Secondary Fallback Source: Paired Smartphone GPS via BLE
        if (_hasFallback && (now - _fallbackTimestamp <= 60000)) {
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

        outLat = 0.0;
        outLon = 0.0;
        return GPS_SOURCE_NONE;
    }

    bool hasHardwareFix() const { return _hasFix; }
    uint8_t getSatellites() const { return _satellites; }
    float getAltitude() const { return _altitude; }
    double getRawLat() const { return _latitude; }
    double getRawLon() const { return _longitude; }
};

#endif // GPS_MANAGER_H
