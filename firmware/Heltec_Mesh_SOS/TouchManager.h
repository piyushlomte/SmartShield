#ifndef TOUCH_MANAGER_H
#define TOUCH_MANAGER_H

#include <Arduino.h>
#include "Config.h"

enum ButtonGesture {
    GESTURE_NONE = 0,
    GESTURE_SHORT_TAP,      // Switch OLED page / Wake screen
    GESTURE_DOUBLE_TAP,     // Double-Click -> Instant 'I am OK' Safe Check-in
    GESTURE_LONG_PRESS,     // 3-sec Hold -> Triggers Standard SOS with GPS Coordinates
    GESTURE_TRIPLE_TAP      // 3 Fast Clicks -> Triggers Silent / Stealth SOS with GPS Coordinates
};

// Aliased for backwards compatibility
typedef ButtonGesture TouchGesture;

class ButtonManager {
private:
    uint8_t  _externalPin;
    bool     _externalActiveHigh;
    uint8_t  _onboardPin;
    bool     _onboardActiveHigh;

    bool     _lastRawState = false;
    bool     _debouncedState = false;
    uint32_t _lastDebounceTime = 0;
    const uint32_t _debounceDelay = 40; // ms debounce filter

    uint32_t _pressStartTime = 0;
    bool     _longPressTriggered = false;
    
    uint8_t  _tapCount = 0;
    uint32_t _lastReleaseTime = 0;
    const uint32_t _multiTapWindow = 350; // ms window to register multi-taps

    bool readRawState() {
        // Read external push button / touch sensor
        bool extPressed = false;
        if (_externalPin != 255) {
            int val = digitalRead(_externalPin);
            extPressed = _externalActiveHigh ? (val == HIGH) : (val == LOW);
        }

        // Read onboard PRG button (GPIO 0, Active-LOW)
        bool onboardPressed = false;
        if (_onboardPin != 255) {
            int val = digitalRead(_onboardPin);
            onboardPressed = _onboardActiveHigh ? (val == HIGH) : (val == LOW);
        }

        return extPressed || onboardPressed;
    }

public:
    ButtonManager(uint8_t externalPin = PIN_BUTTON_SOS, 
                  bool externalActiveHigh = BUTTON_ACTIVE_HIGH,
                  uint8_t onboardPin = PIN_ONBOARD_BUTTON,
                  bool onboardActiveHigh = false) 
        : _externalPin(externalPin),
          _externalActiveHigh(externalActiveHigh),
          _onboardPin(onboardPin),
          _onboardActiveHigh(onboardActiveHigh) {}

    void begin() {
        if (_externalPin != 255) {
            if (_externalActiveHigh) {
                pinMode(_externalPin, INPUT_PULLDOWN);
            } else {
                pinMode(_externalPin, INPUT_PULLUP);
            }
        }
        if (_onboardPin != 255) {
            pinMode(_onboardPin, INPUT_PULLUP);
        }
        _debouncedState = readRawState();
        _lastRawState = _debouncedState;
    }

    ButtonGesture update() {
        bool rawReading = readRawState();
        uint32_t now = millis();
        ButtonGesture detectedGesture = GESTURE_NONE;

        // Software debouncing
        if (rawReading != _lastRawState) {
            _lastDebounceTime = now;
        }
        _lastRawState = rawReading;

        if ((now - _lastDebounceTime) > _debounceDelay) {
            if (rawReading != _debouncedState) {
                _debouncedState = rawReading;

                if (_debouncedState) {
                    // Button Transition: Just Pressed DOWN
                    _pressStartTime = now;
                    _longPressTriggered = false;
                } else {
                    // Button Transition: Just RELEASED
                    uint32_t pressDuration = now - _pressStartTime;
                    if (!_longPressTriggered && pressDuration < TOUCH_LONG_PRESS_MS) {
                        _tapCount++;
                        _lastReleaseTime = now;
                        if (_tapCount >= 3) {
                            detectedGesture = GESTURE_TRIPLE_TAP;
                            _tapCount = 0;
                        }
                    }
                }
            }
        }

        // Long Press Check while button is held DOWN
        if (_debouncedState && !_longPressTriggered) {
            if (now - _pressStartTime >= TOUCH_LONG_PRESS_MS) {
                _longPressTriggered = true;
                _tapCount = 0;
                detectedGesture = GESTURE_LONG_PRESS;
            }
        }

        // Multi-tap resolution after release window expires
        if (!_debouncedState && _tapCount > 0) {
            if (now - _lastReleaseTime > _multiTapWindow) {
                if (_tapCount == 1) {
                    detectedGesture = GESTURE_SHORT_TAP;
                } else if (_tapCount == 2) {
                    detectedGesture = GESTURE_DOUBLE_TAP;
                }
                _tapCount = 0;
            }
        }

        return detectedGesture;
    }
};

// Aliased for seamless compatibility
typedef ButtonManager TouchManager;

#endif // TOUCH_MANAGER_H
