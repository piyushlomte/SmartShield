#ifndef RADIO_DRIVER_H
#define RADIO_DRIVER_H

#include <Arduino.h>
#include <SPI.h>
#include "Config.h"
#include "MeshProtocol.h"

// Self-contained, robust SPI driver for SX1262 LoRa transceiver on Heltec WiFi LoRa 32 (V3)
class RadioDriver {
private:
    float _frequency;
    SPISettings _spiSettings;
    bool _initialized = false;

    void select() {
        digitalWrite(PIN_LORA_NSS, LOW);
    }

    void deselect() {
        digitalWrite(PIN_LORA_NSS, HIGH);
    }

    void waitNotBusy() {
        uint32_t start = millis();
        while (digitalRead(PIN_LORA_BUSY) == HIGH) {
            if (millis() - start > 1000) break;
            yield();
        }
    }

    void writeCommand(uint8_t opCode, const uint8_t *data, uint8_t len) {
        waitNotBusy();
        SPI.beginTransaction(_spiSettings);
        select();
        SPI.transfer(opCode);
        for (uint8_t i = 0; i < len; i++) {
            SPI.transfer(data[i]);
        }
        deselect();
        SPI.endTransaction();
    }

    void readCommand(uint8_t opCode, uint8_t *data, uint8_t len) {
        waitNotBusy();
        SPI.beginTransaction(_spiSettings);
        select();
        SPI.transfer(opCode);
        SPI.transfer(0x00); // NOP status byte
        for (uint8_t i = 0; i < len; i++) {
            data[i] = SPI.transfer(0x00);
        }
        deselect();
        SPI.endTransaction();
    }

public:
    RadioDriver() : _frequency(DEFAULT_LORA_FREQ), _spiSettings(2000000, MSBFIRST, SPI_MODE0) {}

    bool begin(float freqMHz = DEFAULT_LORA_FREQ) {
        _frequency = freqMHz;

        // 1. Enable Vext Power (Powers external circuitry, OLED, and RF on Heltec V3)
        pinMode(PIN_VEXT_CTRL, OUTPUT);
        digitalWrite(PIN_VEXT_CTRL, LOW); // LOW = Power ON
        delay(10);

        // 2. Setup SPI & Control Pins
        pinMode(PIN_LORA_NSS, OUTPUT);
        pinMode(PIN_LORA_RST, OUTPUT);
        pinMode(PIN_LORA_BUSY, INPUT);
        pinMode(PIN_LORA_DIO1, INPUT);

        deselect();

        // 3. Hardware Reset Pulse
        digitalWrite(PIN_LORA_RST, LOW);
        delay(20);
        digitalWrite(PIN_LORA_RST, HIGH);
        delay(30);

        SPI.begin(PIN_LORA_SCK, PIN_LORA_MISO, PIN_LORA_MOSI, PIN_LORA_NSS);

        // 4. Set Standby Mode (STDBY_RC = 0x00)
        uint8_t stdbyParam = 0x00;
        writeCommand(0x80, &stdbyParam, 1);

        // 5. Set Regulator Mode to DC-DC for efficiency (Opcode 0x96, 0x01)
        uint8_t regMode = 0x01;
        writeCommand(0x96, &regMode, 1);

        // 6. Set DIO3 as TCXO (1.8V, 5ms timeout = 320 ticks = 0x000140) (Heltec V3 TCXO control)
        uint8_t tcxoParams[4] = {0x02, 0x00, 0x01, 0x40};
        writeCommand(0x97, tcxoParams, 4);

        // 7. Calibrate all blocks (Opcode 0x89)
        uint8_t calibParam = 0x7F;
        writeCommand(0x89, &calibParam, 1);
        delay(10);

        // 8. Set DIO2 as RF Switch Control (Heltec V3 RF Switch)
        uint8_t dio2Params = 0x01;
        writeCommand(0x9D, &dio2Params, 1);

        // 9. Set Packet Type to LoRa (0x01)
        uint8_t pktType = 0x01;
        writeCommand(0x8A, &pktType, 1);

        // 10. Set RF Frequency: Freq = (freqMHz * 32MHz) / 2^25
        uint32_t freqRf = (uint32_t)((double)_frequency * (1 << 25) / 32.0);
        uint8_t freqBuf[4];
        freqBuf[0] = (freqRf >> 24) & 0xFF;
        freqBuf[1] = (freqRf >> 16) & 0xFF;
        freqBuf[2] = (freqRf >> 8) & 0xFF;
        freqBuf[3] = freqRf & 0xFF;
        writeCommand(0x86, freqBuf, 4);

        // 11. Set Buffer Base Address (TX=0, RX=0)
        uint8_t baseAddr[2] = {0x00, 0x00};
        writeCommand(0x8F, baseAddr, 2);

        // 12. Set PA Config for SX1262 (+22dBm output)
        uint8_t paConfig[4] = {0x04, 0x07, 0x00, 0x01};
        writeCommand(0x95, paConfig, 4);

        // 13. Set Tx Params: +22 dBm (0x16), 200us ramp time (0x02)
        uint8_t txParams[2] = {0x16, 0x02};
        writeCommand(0x8E, txParams, 2);

        // 14. Set Modulation Params (SF10, BW125kHz=0x04, CR4/7=0x03, LowDataRateOptimize=0)
        uint8_t modParams[4] = {LORA_SPREADING_FACTOR, 0x04, 0x03, 0x00};
        writeCommand(0x8B, modParams, 4);

        // 15. Set Packet Params: Preamble 12, Explicit header, Max payload 255, CRC ON (0x01), Standard IQ (0x00)
        uint8_t pktParams[6] = {0x00, LORA_PREAMBLE_LENGTH, 0x00, 0xFF, 0x01, 0x00};
        writeCommand(0x8C, pktParams, 6);

        // 16. Set Sync Word (0x34)
        setSyncWord(LORA_SYNC_WORD);

        // 17. Configure DIO IRQ Params (Route TxDone & RxDone to DIO1)
        uint8_t irqParams[8] = {0x02, 0x03, 0x02, 0x03, 0x00, 0x00, 0x00, 0x00};
        writeCommand(0x08, irqParams, 8);

        // 18. Clear IRQ status
        uint8_t clearIrq[2] = {0xFF, 0xFF};
        writeCommand(0x02, clearIrq, 2);

        // 19. Put into continuous RX mode
        startRx();

        _initialized = true;
        return true;
    }

    void setSyncWord(uint8_t syncWord) {
        waitNotBusy();
        SPI.beginTransaction(_spiSettings);
        select();
        SPI.transfer(0x0D); // Write register
        SPI.transfer(0x07); // RegLoRaSyncWordMSB 0x0740
        SPI.transfer(0x40);
        SPI.transfer((syncWord & 0xF0) | 0x04);
        SPI.transfer(((syncWord & 0x0F) << 4) | 0x04);
        deselect();
        SPI.endTransaction();
    }

    void startRx() {
        uint8_t rxParams[3] = {0xFF, 0xFF, 0xFF}; // Continuous RX timeout
        writeCommand(0x82, rxParams, 3);
    }

    bool transmit(const uint8_t *data, uint8_t len) {
        if (!_initialized) return false;

        // Set Standby
        uint8_t stdby = 0x00;
        writeCommand(0x80, &stdby, 1);

        // Set Buffer Base Addr (TX=0, RX=0)
        uint8_t baseAddr[2] = {0x00, 0x00};
        writeCommand(0x8F, baseAddr, 2);

        // Write payload to SX1262 FIFO buffer (Opcode 0x0E)
        waitNotBusy();
        SPI.beginTransaction(_spiSettings);
        select();
        SPI.transfer(0x0E); // WriteBuffer
        SPI.transfer(0x00); // Offset 0
        for (uint8_t i = 0; i < len; i++) {
            SPI.transfer(data[i]);
        }
        deselect();
        SPI.endTransaction();

        // Update Packet Params with payload length
        uint8_t pktParams[6] = {0x00, LORA_PREAMBLE_LENGTH, 0x00, len, 0x01, 0x00};
        writeCommand(0x8C, pktParams, 6);

        // Clear IRQ flags
        uint8_t clearIrq[2] = {0xFF, 0xFF};
        writeCommand(0x02, clearIrq, 2);

        // Set Tx Mode (Timeout 0 = wait until complete)
        uint8_t txTimeout[3] = {0x00, 0x00, 0x00};
        writeCommand(0x83, txTimeout, 3);

        // Wait for TxDone IRQ
        uint32_t start = millis();
        bool txDone = false;
        while (millis() - start < 3000) {
            uint8_t irqStatus[2] = {0, 0};
            readCommand(0x12, irqStatus, 2);
            if (irqStatus[1] & 0x01) { // TxDone bit 0
                txDone = true;
                break;
            }
            delay(5);
        }

        // Return back to continuous RX
        startRx();
        return txDone;
    }

    bool receive(MeshPacket &outPkt) {
        if (!_initialized) return false;

        // Check IRQ status
        uint8_t irqStatus[2] = {0, 0};
        readCommand(0x12, irqStatus, 2);

        if (irqStatus[1] & 0x02) { // RxDone bit 1
            // Clear IRQ
            uint8_t clearIrq[2] = {0xFF, 0xFF};
            writeCommand(0x02, clearIrq, 2);

            // Check for CRC Error (bit 6)
            if (irqStatus[1] & 0x40) {
                startRx();
                return false;
            }

            // Get RX buffer status (payload len and start buffer pointer)
            uint8_t rxBufferStatus[2] = {0, 0};
            readCommand(0x13, rxBufferStatus, 2);
            uint8_t payloadLength = rxBufferStatus[0];
            uint8_t rxStartOffset = rxBufferStatus[1];

            if (payloadLength < sizeof(MeshPacketHeader) || payloadLength > MAX_PACKET_SIZE) {
                startRx();
                return false;
            }

            // Read packet from SX1262 FIFO
            uint8_t rawBuffer[MAX_PACKET_SIZE];
            waitNotBusy();
            SPI.beginTransaction(_spiSettings);
            select();
            SPI.transfer(0x1E); // ReadBuffer
            SPI.transfer(rxStartOffset);
            SPI.transfer(0x00); // NOP
            for (uint8_t i = 0; i < payloadLength; i++) {
                rawBuffer[i] = SPI.transfer(0x00);
            }
            deselect();
            SPI.endTransaction();

            // Read Packet Status (RSSI & SNR)
            uint8_t pktStatus[3] = {0, 0, 0};
            readCommand(0x14, pktStatus, 3);
            int16_t rssi = -pktStatus[0] / 2;
            float snr = (int8_t)pktStatus[1] / 4.0f;

            // Deserialize into MeshPacket
            memcpy(&outPkt.header, rawBuffer, sizeof(MeshPacketHeader));
            if (outPkt.header.magic != MESH_MAGIC_BYTE) {
                startRx();
                return false;
            }

            uint8_t payloadBytes = payloadLength - sizeof(MeshPacketHeader);
            if (payloadBytes > 0 && payloadBytes <= MAX_PAYLOAD_LEN) {
                memcpy(outPkt.payload, rawBuffer + sizeof(MeshPacketHeader), payloadBytes);
                outPkt.payload[payloadBytes] = '\0';
            } else {
                outPkt.payload[0] = '\0';
            }

            outPkt.rssi = rssi;
            outPkt.snr = snr;
            outPkt.timestamp = millis();

            startRx();
            return true;
        } else if (irqStatus[0] != 0 || (irqStatus[1] & 0xF8)) {
            // Clear any error / timeout IRQ
            uint8_t clearIrq[2] = {0xFF, 0xFF};
            writeCommand(0x02, clearIrq, 2);
            startRx();
        }

        return false;
    }

    void setFrequency(float freqMHz) {
        _frequency = freqMHz;
        begin(_frequency);
    }

    float getFrequency() const { return _frequency; }
    bool isInitialized() const { return _initialized; }
};

#endif // RADIO_DRIVER_H

