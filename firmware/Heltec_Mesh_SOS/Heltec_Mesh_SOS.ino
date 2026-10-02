  /*
 * =============================================================================
 * PROJECT: AI-SOS Mesh Intelligence System - ESP32-S3 Firmware
 * HARDWARE: Heltec WiFi LoRa 32 (V3) (ESP32-S3FN8 + SX1262 + SSD1306 OLED)
 * PERIPHERALS: NEO-6M GPS, TTP223 Touch, Vibration Motor, LiPo ADC Monitor
 * ARCHITECTURE: 5-Layer Patent-Oriented Emergency State Machine (51 Features)
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
#include "LandmarkResolver.h"

// =============================================================================
// GLOBAL OBJECTS & STATE
// =============================================================================
RadioDriver       loraRadio;
GpsManager        gpsManager;
ButtonManager     buttonManager(PIN_BUTTON_SOS, BUTTON_ACTIVE_HIGH, PIN_ONBOARD_BUTTON, false);
HapticEngine      haptic(PIN_VIBRATION_MOTOR);
LandmarkResolver  g_landmarkResolver;
DisplayManager    display;
BatteryMonitor    battery(PIN_BATTERY_ADC, PIN_VBAT_CTRL);
BleBridge         ble;
DeduplicationTable dedupTable;
PriorityTxQueue   txQueue;

// Node Identification & Telemetry
uint16_t g_nodeId = 0x0001;
uint16_t g_packetSeq = 0;
uint16_t g_relayedPackets = 0;

// Emergency State Machine & AI Risk Engine
EmergencyLifecycleState g_lifecycleState = STATE_NORMAL;
bool     g_isSosActive = false;
bool     g_isSilentSos = false;
uint8_t  g_currentRiskScore = 0;
uint8_t  g_currentConfidence = 0;
uint8_t  g_signalAnomalyScore = 0;
uint16_t g_timeToReserveMins = 720;
uint16_t g_rescueLockToken = 0;
uint8_t  g_sosRepeatCount = 0;
uint8_t  g_retryCount = 0;
uint32_t g_validationStartTime = 0;
bool     g_isValidating = false;

// §10.3 Dead-Man's-Switch / Passive Check-In Mode State
bool     g_deadManEnabled = false;
uint32_t g_deadManIntervalMs = 900000; // 15 minutes default
uint32_t g_lastDeadManCheckin = 0;
bool     g_deadManPromptActive = false;
uint32_t g_deadManPromptStartTime = 0;

uint32_t g_lastSosBeaconTime = 0;
uint32_t g_lastNormalBeaconTime = 0;
char     g_lastDistressMessage[64] = "Distress Emergency!";

// §10.1 RF Signal Fingerprinting History
int16_t  g_lastRxRssi = -90;
float    g_lastRxSnr = 0.0f;
int16_t  g_rssiHistory[4] = {-90, -90, -90, -90};
uint32_t g_rssiTimeHistory[4] = {0, 0, 0, 0};
uint8_t  g_rssiIdx = 0;

// §10.6 Predictive Battery-Health State
uint8_t  g_initialBatteryPct = 100;
uint32_t g_bootTimeMs = 0;
uint32_t g_lastMessageDisplayTime = 0;

// Forward declarations
void handleIncomingBleCommand(const String &cmdJson);
void handleBleConnection(bool connected);
void evaluateAiEmergencyMetrics(bool isRepeated, bool isAckReceived);
void evaluateSignalAnomaly(int16_t currentRssi);
void updatePredictiveBatteryModel();
void startSosValidation(const char *distressText, bool silent);
void commitEmergencySos(const char *distressText, bool silent);
void broadcastEmergencySos(const char *distressText, bool silent);
void broadcastCancelSosOverMesh(bool isSilentDuress);
void sendRescueResponseOverMesh(uint16_t targetNode, const char *responseMsg);
void broadcastPositionBeacon();
void broadcastSafeCheckIn();
void sendChatOverMesh(uint16_t targetNode, const char *msgText);
uint32_t calculateAdaptiveRetryInterval();

// =============================================================================
// UNIQUE NODE ID INITIALIZATION
// =============================================================================
void initNodeId() {
    uint64_t chipId = ESP.getEfuseMac();
    g_nodeId = (uint16_t)(chipId & 0xFFFF);
    if (g_nodeId == 0x0000 || g_nodeId == BROADCAST_NODE_ID) {
        g_nodeId = 0x1A2B;
    }
}

void handleBleConnection(bool connected) {
    if (connected) {
        char jsonBuf[260];
        snprintf(jsonBuf, sizeof(jsonBuf),
                 "{\"type\":\"NODE_STATUS\",\"sender\":%d,\"id\":%d,\"bat\":%d,\"freq\":%.3f,\"risk\":%d,\"conf\":%d,\"sig_anom\":%d,\"time_res\":%d,\"state\":%d,\"nodes\":0}",
                 g_nodeId, g_nodeId, battery.getPercentage(), loraRadio.getFrequency(),
                 g_currentRiskScore, g_currentConfidence, g_signalAnomalyScore, g_timeToReserveMins,
                 (uint8_t)g_lifecycleState);
        ble.sendJsonFrame(jsonBuf);
    }
}

// =============================================================================
// §10.1 RF SIGNAL FINGERPRINTING FOR SITUATIONAL INFERENCE
// =============================================================================
void evaluateSignalAnomaly(int16_t currentRssi) {
    uint32_t now = millis();
    g_rssiHistory[g_rssiIdx] = currentRssi;
    g_rssiTimeHistory[g_rssiIdx] = now;
    g_rssiIdx = (g_rssiIdx + 1) % 4;

    int16_t oldestRssi = g_rssiHistory[g_rssiIdx];
    uint32_t deltaT = now - g_rssiTimeHistory[g_rssiIdx];

    // Sudden rapid attenuation: RSSI drops >18 dB in under 40 seconds (submersion, cave-in, burial)
    if (deltaT > 5000 && deltaT <= 45000) {
        int drop = oldestRssi - currentRssi;
        if (drop >= 18) {
            g_signalAnomalyScore = min(95, (int)(drop * 3.2));
            Serial.printf("[SIGNAL FINGERPRINT] Rapid RF Attenuation Detected! Drop:%ddB in %ds -> Anomaly Score:%d\n",
                          drop, deltaT / 1000, g_signalAnomalyScore);
        } else {
            g_signalAnomalyScore = 0;
        }
    }
}

// =============================================================================
// §10.6 PREDICTIVE BATTERY-HEALTH DEGRADATION MODEL
// =============================================================================
void updatePredictiveBatteryModel() {
    uint32_t elapsedMs = millis() - g_bootTimeMs;
    uint8_t curBat = battery.getPercentage();

    if (elapsedMs > 60000 && g_initialBatteryPct > curBat) {
        float pctLost = (float)(g_initialBatteryPct - curBat);
        float msPerPct = (float)elapsedMs / pctLost;
        float remainingPctToReserve = max(0.0f, (float)(curBat - 5)); // Until 5% reserve
        g_timeToReserveMins = (uint16_t)((remainingPctToReserve * msPerPct) / 60000.0f);
    } else {
        // Nominal baseline calculation: ~12 hours on full charge
        g_timeToReserveMins = (uint16_t)((curBat / 100.0f) * 720.0f);
    }
}

// =============================================================================
// EXPLAINABLE EDGE AI RISK & CONFIDENCE ENGINE
// =============================================================================
void evaluateAiEmergencyMetrics(bool isRepeated, bool isAckReceived) {
    uint8_t bat = battery.getPercentage();
    double lat, lon;
    GpsSource src = gpsManager.getEffectiveCoordinates(lat, lon);
    bool hasGps = (src != GPS_SOURCE_NONE);

    // 1. Calculate Base Risk Score (0 - 100)
    int score = 0;
    if (g_isSosActive || g_isValidating) {
        score += 40; // Base manual trigger
    }
    if (isRepeated || g_sosRepeatCount > 1) {
        score += min(25, (int)(g_sosRepeatCount * 12)); // Repeated activation
    }
    if (!isAckReceived && g_retryCount > 0) {
        score += min(20, (int)(g_retryCount * 8)); // Unacknowledged retries
    }
    if (g_signalAnomalyScore > 0) {
        score += (int)(g_signalAnomalyScore * 0.25f); // §10.1 Signal Anomaly fusion
    }
    if (bat <= 10) {
        score += 15; // Critical power failure risk
    } else if (bat <= 20) {
        score += 8;
    }
    if (g_lastRxSnr < -6.0f) {
        score += 10; // Degraded communication link
    }

    g_currentRiskScore = (uint8_t)constrain(score, 0, 100);

    // 2. Calculate Confidence Score (0 - 100%)
    int conf = 60;
    if (hasGps) {
        conf += 20;
        if (gpsManager.getSatellites() >= 6) conf += 10;
    }
    if (g_lastRxRssi > -95) {
        conf += 10;
    }
    g_currentConfidence = (uint8_t)constrain(conf, 10, 100);

    // Maintain consistent mesh Spreading Factor (LORA_SPREADING_FACTOR = SF10) across all nodes
    loraRadio.setModulationProfile(LORA_SPREADING_FACTOR, 0x04, 0x03, 0x00);
}

uint32_t calculateAdaptiveRetryInterval() {
    if (g_lastRxSnr >= 2.0f) {
        return 4000; // Strong link: 4s fast retry
    } else if (g_lastRxSnr >= -5.0f) {
        return 7000; // Average link: 7s retry
    } else {
        return 11000 + ((uint32_t)g_retryCount * 2000); // Congested/Degraded: Anti-collision backoff
    }
}

// =============================================================================
// ROBUST JSON PARSER HELPERS
// =============================================================================
static String extractJsonStr(const String &json, const String &key, const String &fallback = "") {
    String search = "\"" + key + "\":\"";
    int idx = json.indexOf(search);
    if (idx >= 0) {
        int start = idx + search.length();
        int end = json.indexOf("\"", start);
        if (end > start) return json.substring(start, end);
    }
    return fallback;
}

static long extractJsonInt(const String &json, const String &key, long fallback = 0) {
    String search = "\"" + key + "\":";
    int idx = json.indexOf(search);
    if (idx >= 0) {
        int start = idx + search.length();
        while (start < json.length() && (json[start] == ' ' || json[start] == '"')) start++;
        int end = start;
        while (end < json.length() && (isDigit(json[end]) || json[end] == '-')) end++;
        if (end > start) return json.substring(start, end).toInt();
    }
    return fallback;
}

static double extractJsonFloat(const String &json, const String &key, double fallback = 0.0) {
    String search = "\"" + key + "\":";
    int idx = json.indexOf(search);
    if (idx >= 0) {
        int start = idx + search.length();
        while (start < json.length() && (json[start] == ' ' || json[start] == '"')) start++;
        int end = start;
        while (end < json.length() && (isDigit(json[end]) || json[end] == '-' || json[end] == '.')) end++;
        if (end > start) return json.substring(start, end).toDouble();
    }
    return fallback;
}

// =============================================================================
// BLE COMMAND HANDLER (Receives commands from Flutter App)
// =============================================================================
void handleIncomingBleCommand(const String &jsonStr) {
    Serial.printf("[BLE CMD RX] %s\n", jsonStr.c_str());

    if (jsonStr.indexOf("\"cmd\":\"CHAT\"") >= 0) {
        uint16_t dst = (uint16_t)extractJsonInt(jsonStr, "dst", BROADCAST_NODE_ID);
        String msg = extractJsonStr(jsonStr, "msg", "");
        double chatLat = extractJsonFloat(jsonStr, "lat", 0.0);
        double chatLon = extractJsonFloat(jsonStr, "lon", 0.0);
        if (chatLat != 0.0 || chatLon != 0.0) {
            gpsManager.setPhoneFallback(chatLat, chatLon);
        }
        if (msg.length() > 0) {
            sendChatOverMesh(dst, msg.c_str());
        }
    } else if (jsonStr.indexOf("\"cmd\":\"GET_STATUS\"") >= 0) {
        char jsonBuf[260];
        snprintf(jsonBuf, sizeof(jsonBuf),
                 "{\"type\":\"NODE_STATUS\",\"sender\":%d,\"id\":%d,\"bat\":%d,\"freq\":%.3f,\"risk\":%d,\"conf\":%d,\"sig_anom\":%d,\"time_res\":%d,\"state\":%d,\"nodes\":0}",
                 g_nodeId, g_nodeId, battery.getPercentage(), loraRadio.getFrequency(),
                 g_currentRiskScore, g_currentConfidence, g_signalAnomalyScore, g_timeToReserveMins,
                 (uint8_t)g_lifecycleState);
        ble.sendJsonFrame(jsonBuf);
    } else if (jsonStr.indexOf("\"cmd\":\"SOS_RESPONSE\"") >= 0) {
        uint16_t targetNode = (uint16_t)extractJsonInt(jsonStr, "target", BROADCAST_NODE_ID);
        String text = extractJsonStr(jsonStr, "text", "Help is on the way!");
        sendRescueResponseOverMesh(targetNode, text.c_str());
    } else if (jsonStr.indexOf("\"cmd\":\"SOS\"") >= 0) {
        bool silent = (jsonStr.indexOf("\"silent\":true") >= 0);
        String text = extractJsonStr(jsonStr, "text", "Emergency Assistance Required!");
        double lat = extractJsonFloat(jsonStr, "lat", 0.0);
        double lon = extractJsonFloat(jsonStr, "lon", 0.0);
        if (lat != 0.0 || lon != 0.0) {
            gpsManager.setPhoneFallback(lat, lon);
        }
        commitEmergencySos(text.c_str(), silent);
    } else if (jsonStr.indexOf("\"cmd\":\"CANCEL_SOS\"") >= 0) {
        bool isDuress = (jsonStr.indexOf("\"duress\":true") >= 0);
        broadcastCancelSosOverMesh(isDuress);
    } else if (jsonStr.indexOf("\"cmd\":\"DEAD_MAN_CONFIG\"") >= 0) {
        g_deadManEnabled = (jsonStr.indexOf("\"enabled\":true") >= 0);
        long intSec = extractJsonInt(jsonStr, "interval_sec", 900);
        g_deadManIntervalMs = (uint32_t)intSec * 1000;
        g_lastDeadManCheckin = millis();
        Serial.printf("[DEAD MAN] Configured: Enabled=%s, Interval=%ds\n", g_deadManEnabled ? "YES" : "NO", intSec);
    } else if (jsonStr.indexOf("\"cmd\":\"CHECKIN_ACK\"") >= 0) {
        g_deadManPromptActive = false;
        g_lastDeadManCheckin = millis();
        haptic.play(HAPTIC_CONFIRM_SHORT);
        Serial.println("[DEAD MAN] Check-In Acknowledged by User.");
    } else if (jsonStr.indexOf("\"cmd\":\"PHONE_GPS\"") >= 0 || jsonStr.indexOf("\"cmd\":\"SET_LANDMARK\"") >= 0) {
        double lat = extractJsonFloat(jsonStr, "lat", 0.0);
        double lon = extractJsonFloat(jsonStr, "lon", 0.0);
        if (lat != 0.0 || lon != 0.0) {
            gpsManager.setPhoneFallback(lat, lon);
        }
        String area = extractJsonStr(jsonStr, "area", "");
        String near = extractJsonStr(jsonStr, "near", "");
        if (area.length() > 0 || near.length() > 0) {
            g_landmarkResolver.setDynamicLandmark(area.c_str(), near.c_str());
            Serial.printf("[LANDMARK SYNC] Received Landmark: Area='%s', Near='%s'\n", area.c_str(), near.c_str());
        }
    } else if (jsonStr.indexOf("\"cmd\":\"SET_FREQ\"") >= 0) {
        float f = (float)extractJsonFloat(jsonStr, "freq", 0.0);
        if (f >= 400.0f && f <= 950.0f) {
            loraRadio.setFrequency(f);
        }
    }
}

// =============================================================================
// MESH TRANSMISSION HELPERS
// =============================================================================
void sendChatOverMesh(uint16_t targetNode, const char *msgText) {
    if (battery.getVoltage() >= 2.50f && battery.getPercentage() <= 3) {
        Serial.println("[BATTERY LOCKDOWN] Chat blocked: <3% Battery Reserve!");
        return;
    }

    MeshPacket pkt;
    initPacket(pkt, ++g_packetSeq, g_nodeId, targetNode, PKT_TYPE_CHAT, PRIORITY_NORMAL, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();
    pkt.header.riskScore = g_currentRiskScore;
    pkt.header.confidenceScore = g_currentConfidence;
    pkt.header.signalAnomalyScore = g_signalAnomalyScore;
    pkt.header.timeToReserveMins = g_timeToReserveMins;
    pkt.header.lifecycleState = (uint8_t)g_lifecycleState;

    size_t len = min(strlen(msgText), (size_t)MAX_PAYLOAD_LEN);
    memcpy(pkt.payload, msgText, len);
    pkt.payload[len] = '\0';
    pkt.header.payloadLen = len;

    txQueue.push(pkt);
    haptic.play(HAPTIC_CONFIRM_SHORT);
    display.showMessagePage(targetNode, msgText, 0);

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
    pkt.header.riskScore = 30;
    pkt.header.confidenceScore = 95;
    pkt.header.rescueLockToken = g_nodeId; // §10.5 Rescue-Claim Lock Token
    pkt.header.lifecycleState = (uint8_t)STATE_RESCUE_ACCEPTED;

    size_t len = min(strlen(responseMsg), (size_t)MAX_PAYLOAD_LEN);
    memcpy(pkt.payload, responseMsg, len);
    pkt.payload[len] = '\0';
    pkt.header.payloadLen = len;

    txQueue.push(pkt);
    haptic.play(HAPTIC_CONFIRM_SHORT);
    display.showRescueResponsePage(targetNode, responseMsg);

    char ackBuf[128];
    snprintf(ackBuf, sizeof(ackBuf),
             "{\"type\":\"TX_CONFIRM\",\"pkt_id\":%d,\"dst\":%d}",
             g_packetSeq, targetNode);
    ble.sendJsonFrame(ackBuf);
}

void startSosValidation(const char *distressText, bool silent) {
    g_isValidating = true;
    g_validationStartTime = millis();
    g_lifecycleState = STATE_VALIDATING;
    strncpy(g_lastDistressMessage, distressText, sizeof(g_lastDistressMessage) - 1);
    g_isSilentSos = silent;

    haptic.play(HAPTIC_CONFIRM_SHORT);
    Serial.println("[VALIDATION] 3-Second SOS Validation Grace Period Started...");
}

void commitEmergencySos(const char *distressText, bool silent) {
    g_isValidating = false;
    g_isSosActive = true;
    g_isSilentSos = silent;
    g_lifecycleState = STATE_SOS_GENERATED;
    g_sosRepeatCount++;
    strncpy(g_lastDistressMessage, distressText, sizeof(g_lastDistressMessage) - 1);
    g_lastSosBeaconTime = millis();

    evaluateAiEmergencyMetrics(true, false);
    broadcastEmergencySos(distressText, silent);
}

void broadcastEmergencySos(const char *distressText, bool silent) {
    MeshPacket pkt;
    PacketType type = silent ? PKT_TYPE_SILENT_SOS : PKT_TYPE_SOS;
    initPacket(pkt, ++g_packetSeq, g_nodeId, BROADCAST_NODE_ID, type, PRIORITY_EMERGENCY, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();
    pkt.header.riskScore = g_currentRiskScore;
    pkt.header.confidenceScore = g_currentConfidence;
    pkt.header.signalAnomalyScore = g_signalAnomalyScore;
    pkt.header.timeToReserveMins = g_timeToReserveMins;
    pkt.header.rescueLockToken = g_rescueLockToken;
    pkt.header.lifecycleState = (uint8_t)g_lifecycleState;
    pkt.header.retryCount = g_retryCount;

    size_t len = min(strlen(distressText), (size_t)MAX_PAYLOAD_LEN);
    memcpy(pkt.payload, distressText, len);
    pkt.payload[len] = '\0';
    pkt.header.payloadLen = len;

    txQueue.push(pkt);

    haptic.play(HAPTIC_SOS_TRIGGERED);
    haptic.setRescueBeacon(true);
    display.showSosAlert(g_nodeId, lat, lon, distressText);

    char jsonBuf[340];
    snprintf(jsonBuf, sizeof(jsonBuf),
             "{\"type\":\"SOS_TRIGGERED\",\"sender\":%d,\"lat\":%.6f,\"lon\":%.6f,\"gps_src\":%d,\"text\":\"%s\",\"risk\":%d,\"conf\":%d,\"sig_anom\":%d,\"time_res\":%d,\"state\":%d,\"silent\":%s}",
             g_nodeId, lat, lon, pkt.header.gpsSource, distressText,
             g_currentRiskScore, g_currentConfidence, g_signalAnomalyScore, g_timeToReserveMins,
             (uint8_t)g_lifecycleState, silent ? "true" : "false");
    ble.sendJsonFrame(jsonBuf);
}

void broadcastCancelSosOverMesh(bool isSilentDuress) {
    g_isSosActive = false;
    g_isSilentSos = false;
    g_isValidating = false;
    g_sosRepeatCount = 0;
    g_retryCount = 0;
    g_currentRiskScore = 0;
    haptic.setRescueBeacon(false);
    display.setStealth(false);
    haptic.play(HAPTIC_CONFIRM_SHORT);

    MeshPacket pkt;
    PacketType type = isSilentDuress ? PKT_TYPE_SILENT_CANCEL : PKT_TYPE_SOS_CANCEL;
    g_lifecycleState = isSilentDuress ? STATE_SILENT_CANCEL : STATE_RESOLVED;

    initPacket(pkt, ++g_packetSeq, g_nodeId, BROADCAST_NODE_ID, type, PRIORITY_EMERGENCY, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();
    pkt.header.riskScore = isSilentDuress ? 35 : 0;
    pkt.header.confidenceScore = 95;
    pkt.header.lifecycleState = (uint8_t)g_lifecycleState;
    pkt.header.payloadLen = 0;

    txQueue.push(pkt);
    display.showSosCancelledPage(g_nodeId);

    char jsonBuf[160];
    snprintf(jsonBuf, sizeof(jsonBuf),
             "{\"type\":\"SOS_CANCELLED\",\"sender\":%d,\"duress\":%s}",
             g_nodeId, isSilentDuress ? "true" : "false");
    ble.sendJsonFrame(jsonBuf);
}

void broadcastPositionBeacon() {
    if (battery.getPercentage() <= 10) {
        return;
    }

    MeshPacket pkt;
    initPacket(pkt, ++g_packetSeq, g_nodeId, BROADCAST_NODE_ID, PKT_TYPE_POSITION, PRIORITY_BACKGROUND, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();
    pkt.header.riskScore = g_currentRiskScore;
    pkt.header.confidenceScore = g_currentConfidence;
    pkt.header.signalAnomalyScore = g_signalAnomalyScore;
    pkt.header.timeToReserveMins = g_timeToReserveMins;
    pkt.header.lifecycleState = (uint8_t)g_lifecycleState;
    pkt.header.payloadLen = 0;

    txQueue.push(pkt);
}

void broadcastSafeCheckIn() {
    MeshPacket pkt;
    initPacket(pkt, ++g_packetSeq, g_nodeId, BROADCAST_NODE_ID, PKT_TYPE_SAFE_CHECKIN, PRIORITY_HIGH, MAX_HOP_COUNT);

    double lat, lon;
    pkt.header.gpsSource = (uint8_t)gpsManager.getEffectiveCoordinates(lat, lon);
    pkt.header.latitude = (int32_t)(lat * 1e7);
    pkt.header.longitude = (int32_t)(lon * 1e7);
    pkt.header.batteryPercent = battery.getPercentage();
    pkt.header.riskScore = 0;
    pkt.header.confidenceScore = 100;
    pkt.header.signalAnomalyScore = 0;
    pkt.header.timeToReserveMins = g_timeToReserveMins;
    pkt.header.lifecycleState = (uint8_t)STATE_NORMAL;

    const char *safeMsg = "Safe & OK Check-In";
    memcpy(pkt.payload, safeMsg, strlen(safeMsg));
    pkt.header.payloadLen = strlen(safeMsg);

    txQueue.push(pkt);
    haptic.play(HAPTIC_CONFIRM_SHORT);
    display.wakeUp();
    display.showMessagePage(g_nodeId, "CHECK-IN: SAFE & OK", 0);
    g_lastMessageDisplayTime = millis();
    Serial.println("[CHECK-IN] Double-Tap Registered: Broadcasted 'Safe & OK' across mesh.");

    if (ble.isConnected()) {
        char jsonBuf[220];
        snprintf(jsonBuf, sizeof(jsonBuf),
                 "{\"type\":\"SAFE_CHECKIN\",\"sender\":%d,\"lat\":%.6f,\"lon\":%.6f,\"bat\":%d}",
                 g_nodeId, lat, lon, battery.getPercentage());
        ble.sendJsonFrame(jsonBuf);
    }
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

    g_bootTimeMs = millis();
    initNodeId();

    display.begin();
    display.clear();
    display.printString(10, 20, "AI-SOS Mesh Intel");
    display.printString(10, 35, "Initializing Radio...");
    display.render();

    haptic.begin();
    buttonManager.begin();
    battery.begin();
    g_initialBatteryPct = battery.getPercentage();
    gpsManager.begin();

    if (!loraRadio.begin(DEFAULT_LORA_FREQ)) {
        display.printString(10, 50, "Radio Init FAIL!");
        display.render();
    } else {
        char freqMsg[32];
        snprintf(freqMsg, sizeof(freqMsg), "Radio %.1fMHz OK!", DEFAULT_LORA_FREQ);
        display.printString(10, 50, freqMsg);
        display.render();
    }
    delay(1000);

    char bleName[32];
    snprintf(bleName, sizeof(bleName), "MeshSOS-%04X", g_nodeId);
    ble.begin(bleName, handleIncomingBleCommand, handleBleConnection);

    haptic.play(HAPTIC_CONFIRM_SHORT);

    double initLat, initLon;
    gpsManager.getEffectiveCoordinates(initLat, initLon);
    display.showStatusPage(g_nodeId, battery.getPercentage(), ble.isConnected(),
                           initLat, initLon, gpsManager.getSatellites(), g_relayedPackets, DEFAULT_LORA_FREQ);
}

// =============================================================================
// MAIN EXECUTION LOOP
// =============================================================================
void loop() {
    uint32_t now = millis();

    // 1. Update Subsystems & Predictive Models
    haptic.update();
    battery.update();
    gpsManager.update();
    ble.update();
    updatePredictiveBatteryModel();

    // 2. SOS Validation Expiration Check
    if (g_isValidating && (now - g_validationStartTime >= 3000)) {
        commitEmergencySos(g_lastDistressMessage, g_isSilentSos);
    }

    // 3. §10.3 Dead-Man's-Switch / Passive Check-In Monitoring
    if (g_deadManEnabled && !g_isSosActive) {
        if (!g_deadManPromptActive && (now - g_lastDeadManCheckin >= g_deadManIntervalMs)) {
            g_deadManPromptActive = true;
            g_deadManPromptStartTime = now;
            haptic.play(HAPTIC_CONFIRM_SHORT);
            Serial.println("[DEAD MAN] Passive Check-In Prompt Triggered (60s countdown)...");
        } else if (g_deadManPromptActive && (now - g_deadManPromptStartTime >= 60000)) {
            // Missed check-in window -> auto-generate emergency event
            g_deadManPromptActive = false;
            Serial.println("[DEAD MAN] User failed to check in! Escalating to Emergency SOS...");
            commitEmergencySos("Passive Check-In Missed / Inactivity Anomaly", false);
        }
    }

    // 4. Decode Physical Push Button / Touch Gestures
    ButtonGesture gesture = buttonManager.update();
    if (gesture == GESTURE_SHORT_TAP || gesture == GESTURE_LONG_PRESS) {
        if (g_deadManPromptActive) {
            // User acknowledged check-in
            g_deadManPromptActive = false;
            g_lastDeadManCheckin = now;
            haptic.play(HAPTIC_CONFIRM_SHORT);
            Serial.println("[DEAD MAN] Check-In Confirmed via Button Tap.");
        } else if (g_isValidating) {
            Serial.println("[BUTTON] User cancelled during 3s grace window! FALSE ALARM AVERTED.");
            g_isValidating = false;
            g_lifecycleState = STATE_RESOLVED;
            g_currentRiskScore = 0;
            haptic.play(HAPTIC_CONFIRM_SHORT);
            display.showSosCancelledPage(g_nodeId);
        } else if (!g_isSosActive) {
            Serial.println("[BUTTON] Triggering 3s SOS Validation Window...");
            display.wakeUp();
            startSosValidation("Emergency Assistance Needed!", false);
        } else {
            Serial.println("[BUTTON] Stopping / Cancelling Active SOS...");
            broadcastCancelSosOverMesh(false);

            double curLat, curLon;
            gpsManager.getEffectiveCoordinates(curLat, curLon);
            display.showStatusPage(g_nodeId, battery.getPercentage(), ble.isConnected(),
                                   curLat, curLon, gpsManager.getSatellites(), g_relayedPackets, DEFAULT_LORA_FREQ);
        }
    } else if (gesture == GESTURE_DOUBLE_TAP) {
        if (!g_isSosActive && !g_isValidating) {
            broadcastSafeCheckIn();
        }
    } else if (gesture == GESTURE_TRIPLE_TAP) {
        Serial.println("[BUTTON] Silent Trigger! Broadcasting Silent SOS + GPS immediately...");
        commitEmergencySos("Silent Distress Signal", true);
    }

    // 5. Process Radio Packet Reception
    MeshPacket rxPkt;
    if (loraRadio.receive(rxPkt)) {
        g_lastRxRssi = rxPkt.rssi;
        g_lastRxSnr = rxPkt.snr;
        evaluateSignalAnomaly(rxPkt.rssi); // §10.1 RF Fingerprinting

        Serial.printf("[LORA RX] Type:%d, Seq:%d, From:0x%04X, To:0x%04X, RSSI:%d dBm, SNR:%.1f dB, Risk:%d, Anom:%d\n",
                      rxPkt.header.packetType, rxPkt.header.packetId, rxPkt.header.senderId,
                      rxPkt.header.recipientId, rxPkt.rssi, rxPkt.snr, rxPkt.header.riskScore, rxPkt.header.signalAnomalyScore);

        if (rxPkt.header.senderId != g_nodeId) {
            if (!dedupTable.isDuplicate(rxPkt.header.senderId, rxPkt.header.packetId)) {
                double rxLat = rxPkt.header.latitude / 1e7;
                double rxLon = rxPkt.header.longitude / 1e7;

                if (rxPkt.header.packetType == PKT_TYPE_SOS || rxPkt.header.packetType == PKT_TYPE_SILENT_SOS) {
                    haptic.play(HAPTIC_INCOMING_ALERT);
                    display.showSosAlert(rxPkt.header.senderId, rxLat, rxLon, (char*)rxPkt.payload);
                    sendAck(rxPkt.header.senderId, rxPkt.header.packetId);

                    char jsonBuf[360];
                    snprintf(jsonBuf, sizeof(jsonBuf),
                             "{\"type\":\"SOS_ALERT\",\"sender\":%d,\"lat\":%.6f,\"lon\":%.6f,\"gps_src\":%d,\"text\":\"%s\",\"risk\":%d,\"conf\":%d,\"sig_anom\":%d,\"time_res\":%d,\"state\":%d,\"rssi\":%d,\"snr\":%.1f,\"hops\":%d}",
                             rxPkt.header.senderId, rxLat, rxLon, rxPkt.header.gpsSource,
                             (char*)rxPkt.payload, rxPkt.header.riskScore, rxPkt.header.confidenceScore,
                             rxPkt.header.signalAnomalyScore, rxPkt.header.timeToReserveMins,
                             rxPkt.header.lifecycleState, rxPkt.rssi, rxPkt.snr, rxPkt.header.hopCount);
                    ble.sendJsonFrame(jsonBuf);

                } else if (rxPkt.header.packetType == PKT_TYPE_SOS_RESPONSE || rxPkt.header.packetType == PKT_TYPE_RESCUE_LOCK) {
                    // §10.5 Rescue Swarm Claim Lock
                    g_rescueLockToken = rxPkt.header.rescueLockToken;

                    if (g_isSosActive || rxPkt.header.recipientId == g_nodeId || rxPkt.header.recipientId == BROADCAST_NODE_ID) {
                        g_lifecycleState = STATE_RESCUE_ACCEPTED;
                        g_isSosActive = false;
                        haptic.setRescueBeacon(false);
                        g_lastMessageDisplayTime = millis();
                        evaluateAiEmergencyMetrics(false, true);
                    }

                    // Play soothing heartbeat pattern to reassure victim
                    haptic.play(HAPTIC_RESCUE_HEARTBEAT);
                    display.showRescueResponsePage(rxPkt.header.senderId, (char*)rxPkt.payload);

                    char jsonBuf[320];
                    snprintf(jsonBuf, sizeof(jsonBuf),
                             "{\"type\":\"SOS_RESPONSE\",\"sender\":%d,\"target\":%d,\"lat\":%.6f,\"lon\":%.6f,\"text\":\"%s\",\"lock_token\":%d,\"rssi\":%d,\"snr\":%.1f,\"state\":4}",
                             rxPkt.header.senderId, rxPkt.header.recipientId, rxLat, rxLon, (char*)rxPkt.payload, g_rescueLockToken, rxPkt.rssi, rxPkt.snr);
                    ble.sendJsonFrame(jsonBuf);

                } else if (rxPkt.header.packetType == PKT_TYPE_SAFE_CHECKIN) {
                    char checkinText[48];
                    snprintf(checkinText, sizeof(checkinText), "Node 0x%04X: SAFE & OK", rxPkt.header.senderId);
                    display.showMessagePage(rxPkt.header.senderId, checkinText, rxPkt.rssi);
                    g_lastMessageDisplayTime = millis();
                    haptic.play(HAPTIC_CONFIRM_SHORT);

                    char jsonBuf[220];
                    snprintf(jsonBuf, sizeof(jsonBuf),
                             "{\"type\":\"SAFE_CHECKIN\",\"sender\":%d,\"lat\":%.6f,\"lon\":%.6f,\"bat\":%d,\"rssi\":%d,\"snr\":%.1f}",
                             rxPkt.header.senderId, rxLat, rxLon, rxPkt.header.batteryPercent, rxPkt.rssi, rxPkt.snr);
                    ble.sendJsonFrame(jsonBuf);

                } else if (rxPkt.header.packetType == PKT_TYPE_SOS_CANCEL || rxPkt.header.packetType == PKT_TYPE_SILENT_CANCEL) {
                    bool isDuress = (rxPkt.header.packetType == PKT_TYPE_SILENT_CANCEL);
                    display.showSosCancelledPage(rxPkt.header.senderId);

                    char jsonBuf[180];
                    snprintf(jsonBuf, sizeof(jsonBuf),
                             "{\"type\":\"SOS_CANCELLED\",\"sender\":%d,\"duress\":%s}",
                             rxPkt.header.senderId, isDuress ? "true" : "false");
                    ble.sendJsonFrame(jsonBuf);

                } else if (rxPkt.header.packetType == PKT_TYPE_CHAT) {
                    if (rxPkt.header.recipientId == g_nodeId || rxPkt.header.recipientId == BROADCAST_NODE_ID) {
                        haptic.play(HAPTIC_INCOMING_ALERT);
                        display.showMessagePage(rxPkt.header.senderId, (char*)rxPkt.payload, rxPkt.rssi);
                        g_lastMessageDisplayTime = millis();
                        sendAck(rxPkt.header.senderId, rxPkt.header.packetId);

                        char jsonBuf[300];
                        snprintf(jsonBuf, sizeof(jsonBuf),
                                 "{\"type\":\"CHAT_MSG\",\"sender\":%d,\"dst\":%d,\"msg\":\"%s\",\"rssi\":%d,\"snr\":%.1f,\"lat\":%.6f,\"lon\":%.6f,\"bat\":%d}",
                                 rxPkt.header.senderId, rxPkt.header.recipientId, (char*)rxPkt.payload,
                                 rxPkt.rssi, rxPkt.snr, rxLat, rxLon, rxPkt.header.batteryPercent);
                        ble.sendJsonFrame(jsonBuf);
                    }

                } else if (rxPkt.header.packetType == PKT_TYPE_ACK) {
                    if (g_isSosActive) {
                        g_lifecycleState = STATE_SOS_RECEIVED;
                        evaluateAiEmergencyMetrics(false, true);
                    }

                    char jsonBuf[160];
                    snprintf(jsonBuf, sizeof(jsonBuf),
                             "{\"type\":\"ACK\",\"sender\":%d,\"pkt_id\":%s,\"rssi\":%d,\"snr\":%.1f,\"state\":%d}",
                             rxPkt.header.senderId, (char*)rxPkt.payload, rxPkt.rssi, rxPkt.snr, (uint8_t)g_lifecycleState);
                    ble.sendJsonFrame(jsonBuf);

                } else if (rxPkt.header.packetType == PKT_TYPE_POSITION) {
                    char jsonBuf[220];
                    snprintf(jsonBuf, sizeof(jsonBuf),
                             "{\"type\":\"NODE_POS\",\"sender\":%d,\"lat\":%.6f,\"lon\":%.6f,\"gps_src\":%d,\"bat\":%d,\"rssi\":%d,\"snr\":%.1f}",
                             rxPkt.header.senderId, rxLat, rxLon, rxPkt.header.gpsSource,
                             rxPkt.header.batteryPercent, rxPkt.rssi, rxPkt.snr);
                    ble.sendJsonFrame(jsonBuf);
                }

                // Mesh Store & Forward
                if (rxPkt.header.packetType != PKT_TYPE_ACK &&
                    rxPkt.header.packetType != PKT_TYPE_POSITION &&
                    rxPkt.header.recipientId != g_nodeId &&
                    rxPkt.header.hopCount < rxPkt.header.maxHops) {
                    rxPkt.header.hopCount++;
                    g_relayedPackets++;
                    txQueue.push(rxPkt);
                }
            }
        }
    }

    // 6. Transmit Queue Processing
    if (txQueue.hasPending()) {
        MeshPacket txPkt;
        if (txQueue.pop(txPkt)) {
            uint8_t rawBuffer[MAX_PACKET_SIZE];
            memcpy(rawBuffer, &txPkt.header, sizeof(MeshPacketHeader));
            if (txPkt.header.payloadLen > 0) {
                memcpy(rawBuffer + sizeof(MeshPacketHeader), txPkt.payload, txPkt.header.payloadLen);
            }
            uint8_t totalLen = sizeof(MeshPacketHeader) + txPkt.header.payloadLen;

            bool ok = loraRadio.transmit(rawBuffer, totalLen);
            Serial.printf("[LORA TX] Type:%d, Seq:%d, Prio:%d, Status:%s\n",
                          txPkt.header.packetType, txPkt.header.packetId, txPkt.header.priority, ok ? "OK" : "FAIL");
            delay(40);
        }
    }

    // 7. Adaptive Retransmission & Escalation
    if (g_isSosActive) {
        uint32_t retryInterval = calculateAdaptiveRetryInterval();
        if (now - g_lastSosBeaconTime >= retryInterval) {
            g_lastSosBeaconTime = now;
            g_retryCount++;
            evaluateAiEmergencyMetrics(false, false);
            broadcastEmergencySos(g_lastDistressMessage, g_isSilentSos);
        }
    }

    // 8. Periodic Position Beacon & Status Sync
    static uint32_t nextBeaconInterval = NORMAL_BEACON_INT_MS;
    uint8_t bat = battery.getPercentage();
    if (!g_isSosActive && (now - g_lastNormalBeaconTime >= nextBeaconInterval)) {
        g_lastNormalBeaconTime = now;
        uint32_t baseInterval = (bat <= 20) ? (NORMAL_BEACON_INT_MS * 3) : NORMAL_BEACON_INT_MS;
        nextBeaconInterval = baseInterval + (uint32_t)random(1000, 5000);
        
        broadcastPositionBeacon();

        if (ble.isConnected()) {
            char jsonBuf[260];
            snprintf(jsonBuf, sizeof(jsonBuf),
                     "{\"type\":\"NODE_STATUS\",\"sender\":%d,\"id\":%d,\"bat\":%d,\"freq\":%.3f,\"risk\":%d,\"conf\":%d,\"sig_anom\":%d,\"time_res\":%d,\"state\":%d,\"nodes\":0}",
                     g_nodeId, g_nodeId, bat, loraRadio.getFrequency(),
                     g_currentRiskScore, g_currentConfidence, g_signalAnomalyScore, g_timeToReserveMins,
                     (uint8_t)g_lifecycleState);
            ble.sendJsonFrame(jsonBuf);
        }
    }

    // 9. Refresh OLED Display Page
    static uint32_t lastDisplayUpdate = 0;
    if ((now - g_lastMessageDisplayTime >= 6000) && (now - lastDisplayUpdate >= 2000)) {
        lastDisplayUpdate = now;
        double curLat, curLon;
        gpsManager.getEffectiveCoordinates(curLat, curLon);
        if (g_isSosActive) {
            display.showSosAlert(g_nodeId, curLat, curLon, g_lastDistressMessage);
        } else {
            display.showStatusPage(g_nodeId, battery.getPercentage(), ble.isConnected(),
                                   curLat, curLon, gpsManager.getSatellites(), g_relayedPackets, DEFAULT_LORA_FREQ);
        }
    }

    yield();
}
