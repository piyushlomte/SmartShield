#ifndef TOUCH_MANAGER_H
#define TOUCH_MANAGER_H

#include <Arduino.h>
#include "Config.h"

enum TouchGesture {
    GESTURE_NONE = 0,
    GESTURE_SHORT_TAP,      // Switch OLED page / Wake screen
    GESTURE_LONG_PRESS,     // 3-sec Hold -> Triggers Standard SOS
    GESTURE_TRIPLE_TAP      // 3 Fast Taps -> Triggers Silent / Stealth SOS
};

class TouchManager {
private:
    uint8_t _pin;
    bool _lastState = LOW;
    uint32_t _pressStartTime = 0;
    bool _longPressTriggered = false;
    
    uint8_t _tapCount = 0;
    uint32_t _firstTapTime = 0;
    uint32_t _lastReleaseTime = 0;

public:
    TouchManager(uint8_t pin) : _pin(pin) {}

    void begin() {
        pinMode(_pin, INPUT);
    }

    TouchGesture update() {
        bool currentState = digitalRead(_pin);
        uint32_t now = millis();
        TouchGesture detectedGesture = GESTURE_NONE;

        // Transition: Touch Started (Rising Edge)
        if (currentState == HIGH && _lastState == LOW) {
            _pressStartTime = now;
            _longPressTriggered = false;
        }

        // State: Holding
        if (currentState == HIGH && _lastState == HIGH) {
            if (!_longPressTriggered && (now - _pressStartTime >= TOUCH_LONG_PRESS_MS)) {
                _longPressTriggered = true;
                _tapCount = 0; // Cancel tap sequences
                detectedGesture = GESTURE_LONG_PRESS;
            }
        }

        // Transition: Touch Released (Falling Edge)
        if (currentState == LOW && _lastState == HIGH) {
            uint32_t duration = now - _pressStartTime;

            if (!_longPressTriggered && duration > 40 && duration < 800) {
                // Count valid short tap
                if (_tapCount == 0 || (now - _firstTapTime > TOUCH_TRIPLE_TAP_WINDOW)) {
                    _tapCount = 1;
                    _firstTapTime = now;
                } else {
                    _tapCount++;
                }
                _lastReleaseTime = now;

                if (_tapCount >= 3) {
                    _tapCount = 0;
                    detectedGesture = GESTURE_TRIPLE_TAP;
                }
            }
        }

        // Check if single tap window expired (resolve single tap)
        if (_tapCount == 1 && (now - _lastReleaseTime > 350) && currentState == LOW) {
            _tapCount = 0;
            if (detectedGesture == GESTURE_NONE) {
                detectedGesture = GESTURE_SHORT_TAP;
            }
        }

        _lastState = currentState;
        return detectedGesture;
    }
};

#endif // TOUCH_MANAGER_H
