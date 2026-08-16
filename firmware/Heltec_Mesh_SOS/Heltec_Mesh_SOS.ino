/*
 * =============================================================================
 * PROJECT: Offline Mesh SOS Communicator - ESP32-S3 Firmware
 * HARDWARE: Heltec WiFi LoRa 32 (V3) (ESP32-S3FN8 + SX1262 + SSD1306 OLED)
 * PERIPHERALS: NEO-6M GPS, TTP223 Touch, Vibration Motor, LiPo ADC Monitor
 * =============================================================================
 */

#include <Arduino.h>
#include "Config.h"
#include "MeshProtocol.h"
#include "PriorityQueue.h"
#include "RadioDriver.h"
#include "GpsManager.h"
#include "TouchManager.h"
#include "HapticEngine.h"
#include "DisplayManager.h"
#include "BatteryMonitor.h"
#include "BleBridge.h"

// =============================================================================
// GLOBAL OBJECTS & STATE
// =============================================================================
RadioDriver       loraRadio;
GpsManager        gpsManager;
TouchManager      touchManager(PIN_TOUCH_SENSOR);
HapticEngine      haptic(PIN_VIBRATION_MOTOR);
DisplayManager    display;
BatteryMonitor    battery(PIN_BATTERY_ADC, PIN_VBAT_CTRL);
BleBridge         ble;
DeduplicationTable dedupTable;
PriorityTxQueue   txQueue;

// Node Identification & Telemetry
uint16_t g_nodeId = 0x0001;
uint16_t g_packetSeq = 0;
uint16_t g_relayedPackets = 0;

// SOS Emergency State
bool     g_isSosActive = false;
bool     g_isSilentSos = false;
uint32_t g_lastSosBeaconTime = 0;
uint32_t g_lastNormalBeaconTime = 0;
char     g_lastDistressMessage[64] = "Distress Emergency!";

// Forward declarations
void handleIncomingBleCommand(const String &cmdJson);
void handleBleConnection(bool connected);
void broadcastEmergencySos(const char *distressText, bool silent);
void broadcastCancelSosOverMesh();
void sendRescueResponseOverMesh(uint16_t targetNode, const char *responseMsg);
void broadcastPositionBeacon();
void sendChatOverMesh(uint16_t targetNode, const char *msgText);

// =============================================================================
// UNIQUE NODE ID INITIALIZATION
// =============================================================================
void initNodeId() {
    uint64_t chipId = ESP.getEfuseMac();
    // Use lower 16 bits of eFuse MAC as unique node address
    g_nodeId = (uint16_t)(chipId & 0xFFFF);
    if (g_nodeId == 0x0000 || g_nodeId == BROADCAST_NODE_ID) {
        g_nodeId = 0x1A2B;
    }
}

void handleBleConnection(bool connected) {
    if (connected) {
        // Send Node Status to Phone immediately
        char jsonBuf[160];
        snprintf(jsonBuf, sizeof(jsonBuf),
                 "{\"type\":\"NODE_STATUS\",\"id\":%d,\"bat\":%d,\"freq\":%.3f,\"nodes\":0}",
                 g_nodeId, battery.getPercentage(), loraRadio.getFrequency());
        ble.sendJsonFrame(jsonBuf);
    }
}

// =============================================================================
// BLE COMMAND HANDLER (Receives commands from Flutter App)
// =============================================================================
void handleIncomingBleCommand(const String &jsonStr) {
    if (jsonStr.indexOf("\"cmd\":\"CHAT\"") >= 0) {
        uint16_t dst = BROADCAST_NODE_ID;
        int dstIdx = jsonStr.indexOf("\"dst\":");
        if (dstIdx >= 0) {
            dst = jsonStr.substring(dstIdx + 6).toInt();
        }
        int msgIdx = jsonStr.indexOf("\"msg\":\"");
        if (msgIdx >= 0) {
            int endIdx = jsonStr.indexOf("\"", msgIdx + 7);
            String msg = jsonStr.substring(msgIdx + 7, endIdx);
            sendChatOverMesh(dst, msg.c_str());
        }
    } else if (jsonStr.indexOf("\"cmd\":\"SOS_RESPONSE\"") >= 0) {
        // 2-Way SOS Rescue Response from paired phone
        uint16_t targetNode = BROADCAST_NODE_ID;
        int targetIdx = jsonStr.indexOf("\"target\":");
        if (targetIdx >= 0) {
            targetNode = jsonStr.substring(targetIdx + 9).toInt();
        }
        String text = "Help is on the way!";
        int textIdx = jsonStr.indexOf("\"text\":\"");
        if (textIdx >= 0) {
            int endIdx = jsonStr.indexOf("\"", textIdx + 8);
            text = jsonStr.substring(textIdx + 8, endIdx);
        }
        sendRescueResponseOverMesh(targetNode, text.c_str());
    } else if (jsonStr.indexOf("\"cmd\":\"SOS\"") >= 0) {
        bool silent = (jsonStr.indexOf("\"silent\":true") >= 0);
        String text = "Emergency Assistance Required!";
        int textIdx = jsonStr.indexOf("\"text\":\"");
        if (textIdx >= 0) {
            int endIdx = jsonStr.indexOf("\"", textIdx + 8);
            text = jsonStr.substring(textIdx + 8, endIdx);
        }

        // Extract direct coordinates from phone if sent with SOS
        int latIdx = jsonStr.indexOf("\"lat\":");
        int lonIdx = jsonStr.indexOf("\"lon\":");
        if (latIdx >= 0 && lonIdx >= 0) {
            double lat = jsonStr.substring(latIdx + 6).toDouble();
            double lon = jsonStr.substring(lonIdx + 6).toDouble();
            if (lat != 0.0 || lon != 0.0) {
                gpsManager.setPhoneFallback(lat, lon);
            }
        }

        broadcastEmergencySos(text.c_str(), silent);
    } else if (jsonStr.indexOf("\"cmd\":\"CANCEL_SOS\"") >= 0) {
        g_isSosActive = false;
        g_isSilentSos = false;
        haptic.setRescueBeacon(false);
        display.setStealth(false);
        haptic.play(HAPTIC_CONFIRM_SHORT);
        broadcastCancelSosOverMesh();
    } else if (jsonStr.indexOf("\"cmd\":\"PHONE_GPS\"") >= 0) {
        int latIdx = jsonStr.indexOf("\"lat\":");
        int lonIdx = jsonStr.indexOf("\"lon\":");
        if (latIdx >= 0 && lonIdx >= 0) {
            double lat = jsonStr.substring(latIdx + 6).toDouble();
            double lon = jsonStr.substring(lonIdx + 6).toDouble();
            gpsManager.setPhoneFallback(lat, lon);
        }
    } else if (jsonStr.indexOf("\"cmd\":\"SET_FREQ\"") >= 0) {
        int freqIdx = jsonStr.indexOf("\"freq\":");
        if (freqIdx >= 0) {
            float f = jsonStr.substring(freqIdx + 7).toFloat();
            if (f >= 400.0f && f <= 950.0f) {
                loraRadio.setFrequency(f);
            }
        }
    }
}

// =============================================================================
// MESH TRANSMISSION HELPERS
// =============================================================================
void sendChatOverMesh(uint16_t targetNode, const char *msgText) {
    MeshPacket pkt;
    initPacket(pkt, ++g_packetSeq, g_nodeId, targetNode, PKT_TYPE_CHAT, PRIORITY_NORMAL, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();

    size_t len = min(strlen(msgText), (size_t)MAX_PAYLOAD_LEN);
    memcpy(pkt.payload, msgText, len);
    pkt.payload[len] = '\0';
    pkt.header.payloadLen = len;

    // Enqueue for LoRa Transmission
    txQueue.push(pkt);
    haptic.play(HAPTIC_CONFIRM_SHORT);
    display.showMessagePage(targetNode, msgText, 0);

    // Send TX confirmation to Phone
    char ackBuf[128];
    snprintf(ackBuf, sizeof(ackBuf),
             "{\"type\":\"TX_CONFIRM\",\"pkt_id\":%d,\"dst\":%d}",
             g_packetSeq, targetNode);
    ble.sendJsonFrame(ackBuf);
}

void sendRescueResponseOverMesh(uint16_t targetNode, const char *responseMsg) {
    MeshPacket pkt;
    initPacket(pkt, ++g_packetSeq, g_nodeId, targetNode, PKT_TYPE_SOS_RESPONSE, PRIORITY_EMERGENCY, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();

    size_t len = min(strlen(responseMsg), (size_t)MAX_PAYLOAD_LEN);
    memcpy(pkt.payload, responseMsg, len);
    pkt.payload[len] = '\0';
    pkt.header.payloadLen = len;

    txQueue.push(pkt);
    haptic.play(HAPTIC_CONFIRM_SHORT);
    display.showRescueResponsePage(targetNode, responseMsg);

    // Confirm to paired phone
    char ackBuf[128];
    snprintf(ackBuf, sizeof(ackBuf),
             "{\"type\":\"TX_CONFIRM\",\"pkt_id\":%d,\"dst\":%d}",
             g_packetSeq, targetNode);
    ble.sendJsonFrame(ackBuf);
}

void broadcastEmergencySos(const char *distressText, bool silent) {
    g_isSosActive = true;
    g_isSilentSos = silent;
    strncpy(g_lastDistressMessage, distressText, sizeof(g_lastDistressMessage) - 1);
    g_lastSosBeaconTime = millis();

    MeshPacket pkt;
    PacketType type = silent ? PKT_TYPE_SILENT_SOS : PKT_TYPE_SOS;
    initPacket(pkt, ++g_packetSeq, g_nodeId, BROADCAST_NODE_ID, type, PRIORITY_EMERGENCY, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();

    size_t len = min(strlen(distressText), (size_t)MAX_PAYLOAD_LEN);
    memcpy(pkt.payload, distressText, len);
    pkt.payload[len] = '\0';
    pkt.header.payloadLen = len;

    // Preempt transmit queue (Pushed to high priority queue)
    txQueue.push(pkt);

    if (!silent) {
        haptic.play(HAPTIC_SOS_TRIGGERED);
        haptic.setRescueBeacon(true);
        display.showSosAlert(g_nodeId, lat, lon, distressText);
    } else {
        display.setStealth(true);
    }

    // Sync SOS state to paired phone
    char jsonBuf[256];
    snprintf(jsonBuf, sizeof(jsonBuf),
             "{\"type\":\"SOS_TRIGGERED\",\"sender\":%d,\"lat\":%.6f,\"lon\":%.6f,\"gps_src\":%d,\"text\":\"%s\",\"silent\":%s}",
             g_nodeId, lat, lon, pkt.header.gpsSource, distressText, silent ? "true" : "false");
    ble.sendJsonFrame(jsonBuf);
}

void broadcastCancelSosOverMesh() {
    MeshPacket pkt;
    initPacket(pkt, ++g_packetSeq, g_nodeId, BROADCAST_NODE_ID, PKT_TYPE_SOS_CANCEL, PRIORITY_EMERGENCY, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();
    pkt.header.payloadLen = 0;

    txQueue.push(pkt);
    display.showSosCancelledPage(g_nodeId);
}

void broadcastPositionBeacon() {
    MeshPacket pkt;
    initPacket(pkt, ++g_packetSeq, g_nodeId, BROADCAST_NODE_ID, PKT_TYPE_POSITION, PRIORITY_NORMAL, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();
    pkt.header.payloadLen = 0;

    txQueue.push(pkt);
}

void sendAck(uint16_t origSender, uint16_t origPacketId) {
    MeshPacket pkt;
    initPacket(pkt, ++g_packetSeq, g_nodeId, origSender, PKT_TYPE_ACK, PRIORITY_HIGH, MAX_HOP_COUNT);
    char buf[16];
    snprintf(buf, sizeof(buf), "%d", origPacketId);
    memcpy(pkt.payload, buf, strlen(buf));
    pkt.header.payloadLen = strlen(buf);
    txQueue.push(pkt);
}

// =============================================================================
// MAIN SETUP
// =============================================================================
void setup() {
    Serial.begin(115200);
    delay(100);

    initNodeId();

    // Initialize OLED Display
    display.begin();
    display.clear();
    display.printString(10, 20, "Heltec Mesh SOS");
    display.printString(10, 35, "Initializing Radio...");
    display.render();

    // Initialize Peripherals
    haptic.begin();
    touchManager.begin();
    battery.begin();
    gpsManager.begin();

    // Initialize SX1262 LoRa Radio
    if (!loraRadio.begin(DEFAULT_LORA_FREQ)) {
        display.printString(10, 50, "Radio Init FAIL!");
        display.render();
    } else {
        display.printString(10, 50, "Radio 433MHz OK!");
        display.render();
    }
    delay(1000);

    // Initialize BLE Server for Phone App sync
    char bleName[32];
    snprintf(bleName, sizeof(bleName), "MeshSOS-%04X", g_nodeId);
    ble.begin(bleName, handleIncomingBleCommand, handleBleConnection);

    haptic.play(HAPTIC_CONFIRM_SHORT);
}

// =============================================================================
// MAIN EXECUTION LOOP
// =============================================================================
void loop() {
    uint32_t now = millis();

    // 1. Update Hardware Drivers & Subsystems
    haptic.update();
    battery.update();
    gpsManager.update();
    ble.update();

    // 2. Decode Capacitive Touch Gestures
    TouchGesture gesture = touchManager.update();
    if (gesture == GESTURE_LONG_PRESS) {
        broadcastEmergencySos("Emergency Assistance Needed!", false);
    } else if (gesture == GESTURE_TRIPLE_TAP) {
        broadcastEmergencySos("Silent Distress Signal", true);
    } else if (gesture == GESTURE_SHORT_TAP) {
        display.nextPage();
        haptic.play(HAPTIC_CONFIRM_SHORT);
    }

    // 3. Process Radio Packet Reception
    MeshPacket rxPkt;
    if (loraRadio.receive(rxPkt)) {
        // Drop any packet originating from our own node (prevents echo & duplicate chat)
        if (rxPkt.header.senderId == g_nodeId) {
            return;
        }

        // Check for deduplication (ignore if seen previously)
        if (!dedupTable.isDuplicate(rxPkt.header.senderId, rxPkt.header.packetId)) {
            double rxLat = rxPkt.header.latitude / 1e7;
            double rxLon = rxPkt.header.longitude / 1e7;

            // Handle Packet Types
            if (rxPkt.header.packetType == PKT_TYPE_SOS || rxPkt.header.packetType == PKT_TYPE_SILENT_SOS) {
                // Incoming Emergency SOS from another node
                haptic.play(HAPTIC_INCOMING_ALERT);
                display.showSosAlert(rxPkt.header.senderId, rxLat, rxLon, (char*)rxPkt.payload);

                // Notify paired phone app over BLE
                char jsonBuf[300];
                snprintf(jsonBuf, sizeof(jsonBuf),
                         "{\"type\":\"SOS_ALERT\",\"sender\":%d,\"lat\":%.6f,\"lon\":%.6f,\"gps_src\":%d,\"text\":\"%s\",\"rssi\":%d,\"snr\":%.1f,\"hops\":%d}",
                         rxPkt.header.senderId, rxLat, rxLon, rxPkt.header.gpsSource,
                         (char*)rxPkt.payload, rxPkt.rssi, rxPkt.snr, rxPkt.header.hopCount);
                ble.sendJsonFrame(jsonBuf);

            } else if (rxPkt.header.packetType == PKT_TYPE_SOS_RESPONSE) {
                // 2-Way Rescue Response from another node
                haptic.play(HAPTIC_SOS_TRIGGERED);
                display.showRescueResponsePage(rxPkt.header.senderId, (char*)rxPkt.payload);

                char jsonBuf[300];
                snprintf(jsonBuf, sizeof(jsonBuf),
                         "{\"type\":\"SOS_RESPONSE\",\"sender\":%d,\"target\":%d,\"lat\":%.6f,\"lon\":%.6f,\"text\":\"%s\",\"rssi\":%d}",
                         rxPkt.header.senderId, rxPkt.header.recipientId, rxLat, rxLon, (char*)rxPkt.payload, rxPkt.rssi);
                ble.sendJsonFrame(jsonBuf);

            } else if (rxPkt.header.packetType == PKT_TYPE_SOS_CANCEL) {
                // SOS has been cancelled / resolved
                display.showSosCancelledPage(rxPkt.header.senderId);

                char jsonBuf[160];
                snprintf(jsonBuf, sizeof(jsonBuf),
                         "{\"type\":\"SOS_CANCELLED\",\"sender\":%d}",
                         rxPkt.header.senderId);
                ble.sendJsonFrame(jsonBuf);

            } else if (rxPkt.header.packetType == PKT_TYPE_CHAT) {
                // Incoming 2-Way Chat Message
                if (rxPkt.header.recipientId == g_nodeId || rxPkt.header.recipientId == BROADCAST_NODE_ID) {
                    haptic.play(HAPTIC_INCOMING_ALERT);
                    display.showMessagePage(rxPkt.header.senderId, (char*)rxPkt.payload, rxPkt.rssi);

                    // Send Delivery ACK back to sender
                    sendAck(rxPkt.header.senderId, rxPkt.header.packetId);

                    // Forward to phone app
                    char jsonBuf[300];
                    snprintf(jsonBuf, sizeof(jsonBuf),
                             "{\"type\":\"CHAT_MSG\",\"sender\":%d,\"dst\":%d,\"msg\":\"%s\",\"rssi\":%d,\"snr\":%.1f,\"lat\":%.6f,\"lon\":%.6f,\"bat\":%d}",
                             rxPkt.header.senderId, rxPkt.header.recipientId, (char*)rxPkt.payload,
                             rxPkt.rssi, rxPkt.snr, rxLat, rxLon, rxPkt.header.batteryPercent);
                    ble.sendJsonFrame(jsonBuf);
                }

            } else if (rxPkt.header.packetType == PKT_TYPE_ACK) {
                char jsonBuf[128];
                snprintf(jsonBuf, sizeof(jsonBuf),
                         "{\"type\":\"ACK\",\"sender\":%d,\"pkt_id\":%s,\"rssi\":%d}",
                         rxPkt.header.senderId, (char*)rxPkt.payload, rxPkt.rssi);
                ble.sendJsonFrame(jsonBuf);

            } else if (rxPkt.header.packetType == PKT_TYPE_POSITION) {
                // Incoming telemetry beacon
                char jsonBuf[200];
                snprintf(jsonBuf, sizeof(jsonBuf),
                         "{\"type\":\"NODE_POS\",\"sender\":%d,\"lat\":%.6f,\"lon\":%.6f,\"gps_src\":%d,\"bat\":%d,\"rssi\":%d,\"snr\":%.1f}",
                         rxPkt.header.senderId, rxLat, rxLon, rxPkt.header.gpsSource,
                         rxPkt.header.batteryPercent, rxPkt.rssi, rxPkt.snr);
                ble.sendJsonFrame(jsonBuf);
            }

            // Mesh Store & Forward / Multi-hop Retransmission
            if (rxPkt.header.hopCount < rxPkt.header.maxHops) {
                rxPkt.header.hopCount++;
                g_relayedPackets++;
                txQueue.push(rxPkt);
            }
        }
    }

    // 4. Radio Transmit Queue Processing (SOS Preempts Normal Packets)
    if (txQueue.hasPending()) {
        MeshPacket txPkt;
        if (txQueue.pop(txPkt)) {
            // Build raw binary wire frame
            uint8_t rawBuffer[MAX_PACKET_SIZE];
            memcpy(rawBuffer, &txPkt.header, sizeof(MeshPacketHeader));
            if (txPkt.header.payloadLen > 0) {
                memcpy(rawBuffer + sizeof(MeshPacketHeader), txPkt.payload, txPkt.header.payloadLen);
            }
            uint8_t totalLen = sizeof(MeshPacketHeader) + txPkt.header.payloadLen;

            // Transmit over SX1262 LoRa
            loraRadio.transmit(rawBuffer, totalLen);

            // Small delay between mesh hops to minimize RF collision
            delay(10);
        }
    }

    // 5. Periodic SOS Emergency Repeat Beacon
    if (g_isSosActive && (now - g_lastSosBeaconTime >= SOS_BEACON_INTERVAL_MS)) {
        g_lastSosBeaconTime = now;
        broadcastEmergencySos(g_lastDistressMessage, g_isSilentSos);
    }

    // 6. Periodic Normal Telemetry Position Beacon
    if (!g_isSosActive && (now - g_lastNormalBeaconTime >= NORMAL_BEACON_INT_MS)) {
        g_lastNormalBeaconTime = now;
        broadcastPositionBeacon();
    }

    // 7. Refresh OLED Display Page (every 2.5s if not showing emergency)
    static uint32_t lastDisplayUpdate = 0;
    if (!g_isSosActive && (now - lastDisplayUpdate >= 2500)) {
        lastDisplayUpdate = now;
        double curLat, curLon;
        gpsManager.getEffectiveCoordinates(curLat, curLon);
        display.showStatusPage(g_nodeId, battery.getPercentage(), ble.isConnected(),
                               curLat, curLon, gpsManager.getSatellites(), g_relayedPackets);
    }

    yield();
}
