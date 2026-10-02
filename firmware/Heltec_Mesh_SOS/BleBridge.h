#ifndef BLE_BRIDGE_H
#define BLE_BRIDGE_H

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "Config.h"
#include "MeshProtocol.h"

typedef void (*BleDataCallback)(const String &data);
typedef void (*BleConnectCallback)(bool connected);

class BleBridge : public BLEServerCallbacks, public BLECharacteristicCallbacks {
private:
    BLEServer *_pServer = nullptr;
    BLECharacteristic *_pTxCharacteristic = nullptr;
    BLECharacteristic *_pRxCharacteristic = nullptr;
    bool _deviceConnected = false;
    BleDataCallback _onRxCallback = nullptr;
    BleConnectCallback _onConnectCallback = nullptr;
    String _rxBuffer = "";

public:
    BleBridge() {}

    void begin(const char *deviceName, BleDataCallback rxCallback, BleConnectCallback connCallback = nullptr) {
        _onRxCallback = rxCallback;
        _onConnectCallback = connCallback;

        // Initialize BLE Device
        BLEDevice::init(deviceName);
        BLEDevice::setMTU(512);

        _pServer = BLEDevice::createServer();
        _pServer->setCallbacks(this);

        BLEService *pService = _pServer->createService(SERVICE_UUID);

        // TX Characteristic (Notify Phone)
        _pTxCharacteristic = pService->createCharacteristic(
            CHAR_TX_UUID,
            BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ
        );
        _pTxCharacteristic->addDescriptor(new BLE2902());

        // RX Characteristic (Write from Phone)
        _pRxCharacteristic = pService->createCharacteristic(
            CHAR_RX_UUID,
            BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
        );
        _pRxCharacteristic->setCallbacks(this);

        pService->start();

        BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
        pAdvertising->addServiceUUID(SERVICE_UUID);

        BLEAdvertisementData advData;
        advData.setFlags(0x06);
        advData.setCompleteServices(BLEUUID(SERVICE_UUID));
        advData.setName(deviceName);
        pAdvertising->setAdvertisementData(advData);

        BLEAdvertisementData scanResponseData;
        scanResponseData.setName(deviceName);
        pAdvertising->setScanResponseData(scanResponseData);

        pAdvertising->setScanResponse(true);
        pAdvertising->setMinPreferred(0x06);
        pAdvertising->setMinPreferred(0x12);
        BLEDevice::startAdvertising();

        Serial.printf("[BLE] Advertising started as: %s\n", deviceName);
    }

    void onConnect(BLEServer *pServer) override {
        _deviceConnected = true;
        Serial.println("[BLE] Client connected!");
        if (_onConnectCallback != nullptr) {
            _onConnectCallback(true);
        }
    }

    void onDisconnect(BLEServer *pServer) override {
        _deviceConnected = false;
        Serial.println("[BLE] Client disconnected! Re-advertising...");
        if (_onConnectCallback != nullptr) {
            _onConnectCallback(false);
        }
        delay(100);
        BLEDevice::startAdvertising();
    }

    void onWrite(BLECharacteristic *pCharacteristic) override {
        size_t len = pCharacteristic->getLength();
        const uint8_t *data = pCharacteristic->getData();
        if (len > 0 && data != nullptr) {
            for (size_t i = 0; i < len; i++) {
                _rxBuffer += (char)data[i];
            }
        }

        // Prevent memory growth from malformed frames
        if (_rxBuffer.length() > 2048) {
            _rxBuffer = "";
        }

        // Process all complete JSON frames in buffer with bracket balancing
        while (true) {
            int startIdx = _rxBuffer.indexOf('{');
            if (startIdx < 0) {
                _rxBuffer = "";
                break;
            }
            if (startIdx > 0) {
                _rxBuffer = _rxBuffer.substring(startIdx);
                startIdx = 0;
            }

            int depth = 0;
            int endIdx = -1;
            bool inQuotes = false;
            bool escape = false;

            for (int i = 0; i < _rxBuffer.length(); i++) {
                char c = _rxBuffer[i];
                if (escape) {
                    escape = false;
                    continue;
                }
                if (c == '\\') {
                    escape = true;
                    continue;
                }
                if (c == '"') {
                    inQuotes = !inQuotes;
                    continue;
                }
                if (!inQuotes) {
                    if (c == '{') depth++;
                    else if (c == '}') {
                        depth--;
                        if (depth == 0) {
                            endIdx = i;
                            break;
                        }
                    }
                }
            }

            if (endIdx > 0) {
                String completeJson = _rxBuffer.substring(0, endIdx + 1);
                _rxBuffer = _rxBuffer.substring(endIdx + 1);
                if (_onRxCallback != nullptr) {
                    _onRxCallback(completeJson);
                }
            } else {
                break;
            }
        }
    }

    void sendJsonFrame(const String &jsonStr) {
        if (_deviceConnected && _pTxCharacteristic != nullptr) {
            Serial.printf("[BLE TX FRAME] %s\n", jsonStr.c_str());
            String frame = jsonStr + "\n";
            int len = frame.length();
            int offset = 0;
            while (offset < len) {
                int chunkSize = min(len - offset, 240);
                String chunk = frame.substring(offset, offset + chunkSize);
                _pTxCharacteristic->setValue((uint8_t*)chunk.c_str(), chunk.length());
                _pTxCharacteristic->notify();
                offset += chunkSize;
                if (offset < len) delay(20);
            }
        } else {
            Serial.println("[BLE TX WARNING] Cannot send JSON: Phone not connected to Heltec via BLE!");
        }
    }

    void update() {
        // BLE maintenance
    }

    bool isConnected() const { return _deviceConnected; }
};

#endif // BLE_BRIDGE_H
