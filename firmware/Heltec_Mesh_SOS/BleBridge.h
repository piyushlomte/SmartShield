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
    bool _oldDeviceConnected = false;
    BleDataCallback _onRxCallback = nullptr;
    BleConnectCallback _onConnectCallback = nullptr;
    String _rxBuffer = "";

public:
    BleBridge() {}

    void begin(const char *deviceName, BleDataCallback rxCallback, BleConnectCallback connCallback = nullptr) {
        _onRxCallback = rxCallback;
        _onConnectCallback = connCallback;
        BLEDevice::init(deviceName);

        _pServer = BLEDevice::createServer();
        _pServer->setCallbacks(this);

        BLEService *pService = _pServer->createService(SERVICE_UUID);

        // TX Characteristic (Notify & Read to Phone)
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
        pAdvertising->setScanResponse(true);
        pAdvertising->setMinPreferred(0x06);
        pAdvertising->setMinPreferred(0x12);
        BLEDevice::startAdvertising();
    }

    void onConnect(BLEServer *pServer) override {
        _deviceConnected = true;
        if (_onConnectCallback != nullptr) {
            _onConnectCallback(true);
        }
    }

    void onDisconnect(BLEServer *pServer) override {
        _deviceConnected = false;
        if (_onConnectCallback != nullptr) {
            _onConnectCallback(false);
        }
    }

    void onWrite(BLECharacteristic *pCharacteristic) override {
        String val = pCharacteristic->getValue();
        if (val.length() == 0) return;
        _rxBuffer += val;

        // Process all complete JSON frames in buffer
        while (_rxBuffer.indexOf('{') >= 0 && _rxBuffer.indexOf('}') >= 0) {
            int startIdx = _rxBuffer.indexOf('{');
            int endIdx = _rxBuffer.indexOf('}', startIdx);
            if (endIdx > startIdx) {
                String completeJson = _rxBuffer.substring(startIdx, endIdx + 1);
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
            String frame = jsonStr + "\n";
            int len = frame.length();
            int offset = 0;
            while (offset < len) {
                int chunkSize = min(len - offset, 240);
                String chunk = frame.substring(offset, offset + chunkSize);
                _pTxCharacteristic->setValue((uint8_t*)chunk.c_str(), chunk.length());
                _pTxCharacteristic->notify();
                offset += chunkSize;
                if (offset < len) delay(10);
            }
        }
    }

    void update() {
        // Handle advertising restart on disconnect
        if (!_deviceConnected && _oldDeviceConnected) {
            delay(200);
            _pServer->startAdvertising();
            _oldDeviceConnected = _deviceConnected;
        }
        if (_deviceConnected && !_oldDeviceConnected) {
            _oldDeviceConnected = _deviceConnected;
        }
    }

    bool isConnected() const { return _deviceConnected; }
};

#endif // BLE_BRIDGE_H
