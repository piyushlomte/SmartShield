#ifndef HAPTIC_ENGINE_H
#define HAPTIC_ENGINE_H

#include <Arduino.h>
#include "Config.h"

enum HapticPattern {
    HAPTIC_NONE = 0,
    HAPTIC_CONFIRM_SHORT,    // 1 short click (100ms) - Button feedback
    HAPTIC_SOS_TRIGGERED,     // 3 long pulses (500ms ON, 200ms OFF) - Emergency active
    HAPTIC_INCOMING_ALERT,   // 2 sharp double pulses - Message/Alert from team
    HAPTIC_RESCUE_BEACON     // Repeating rhythmic pulse for search & rescue locating
};

class HapticEngine {
private:
    uint8_t _pin;
    HapticPattern _currentPattern = HAPTIC_NONE;
    uint32_t _stepTimer = 0;
    uint8_t _patternStep = 0;
    bool _isVibrating = false;
    bool _beaconActive = false;
    uint32_t _lastBeaconPulse = 0;

public:
    HapticEngine(uint8_t pin) : _pin(pin) {}

    void begin() {
        pinMode(_pin, OUTPUT);
        digitalWrite(_pin, LOW);
    }

    void play(HapticPattern pattern) {
        _currentPattern = pattern;
        _patternStep = 0;
        _stepTimer = millis();
        _isVibrating = false;
    }

    void setRescueBeacon(bool enabled) {
        _beaconActive = enabled;
        if (!enabled) {
            digitalWrite(_pin, LOW);
        }
    }

    void update() {
        uint32_t now = millis();

        // Handle active pattern state machine
        if (_currentPattern != HAPTIC_NONE) {
            switch (_currentPattern) {
                case HAPTIC_CONFIRM_SHORT:
                    if (_patternStep == 0) {
                        digitalWrite(_pin, HIGH);
                        if (now - _stepTimer >= 100) {
                            digitalWrite(_pin, LOW);
                            _currentPattern = HAPTIC_NONE;
                        }
                    }
                    break;

                case HAPTIC_SOS_TRIGGERED:
                    // 3 long pulses
                    if (_patternStep == 0) {
                        digitalWrite(_pin, HIGH);
                        if (now - _stepTimer >= 400) { _stepTimer = now; _patternStep++; digitalWrite(_pin, LOW); }
                    } else if (_patternStep == 1) {
                        if (now - _stepTimer >= 150) { _stepTimer = now; _patternStep++; digitalWrite(_pin, HIGH); }
                    } else if (_patternStep == 2) {
                        if (now - _stepTimer >= 400) { _stepTimer = now; _patternStep++; digitalWrite(_pin, LOW); }
                    } else if (_patternStep == 3) {
                        if (now - _stepTimer >= 150) { _stepTimer = now; _patternStep++; digitalWrite(_pin, HIGH); }
                    } else if (_patternStep == 4) {
                        if (now - _stepTimer >= 400) {
                            digitalWrite(_pin, LOW);
                            _currentPattern = HAPTIC_NONE;
                        }
                    }
                    break;

                case HAPTIC_INCOMING_ALERT:
                    // 2 sharp buzzes
                    if (_patternStep == 0) {
                        digitalWrite(_pin, HIGH);
                        if (now - _stepTimer >= 150) { _stepTimer = now; _patternStep++; digitalWrite(_pin, LOW); }
                    } else if (_patternStep == 1) {
                        if (now - _stepTimer >= 100) { _stepTimer = now; _patternStep++; digitalWrite(_pin, HIGH); }
                    } else if (_patternStep == 2) {
                        if (now - _stepTimer >= 150) {
                            digitalWrite(_pin, LOW);
                            _currentPattern = HAPTIC_NONE;
                        }
                    }
                    break;

                default:
                    _currentPattern = HAPTIC_NONE;
                    digitalWrite(_pin, LOW);
                    break;
            }
        }

        // Handle periodic search & rescue beacon pulses if SOS is running
        if (_beaconActive && _currentPattern == HAPTIC_NONE) {
            if (now - _lastBeaconPulse >= 5000) { // Pulse every 5 seconds
                _lastBeaconPulse = now;
                play(HAPTIC_INCOMING_ALERT);
            }
        }
    }
};

#endif // HAPTIC_ENGINE_H
