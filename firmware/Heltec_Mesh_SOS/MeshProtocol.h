#ifndef MESH_PROTOCOL_H
#define MESH_PROTOCOL_H

#include <Arduino.h>

// =============================================================================
// PACKET TYPES & PRIORITY DEFINITIONS (51-Feature Patent-Ready Protocol)
// =============================================================================
enum PacketType : uint8_t {
    PKT_TYPE_CHAT           = 0x01,  // Text chat message (Shared-substrate messaging)
    PKT_TYPE_SOS            = 0x02,  // High priority emergency beacon
    PKT_TYPE_POSITION       = 0x03,  // Periodic GPS telemetry
    PKT_TYPE_ACK            = 0x04,  // Message delivery acknowledgement
    PKT_TYPE_HEALTH         = 0x05,  // Node battery, RSSI, telemetry report
    PKT_TYPE_FALLBACK_REQ   = 0x06,  // Node requesting Phone GPS fallback coordinates
    PKT_TYPE_SILENT_SOS     = 0x07,  // Silent stealth emergency beacon (Covert trigger)
    PKT_TYPE_SOS_RESPONSE   = 0x08,  // 2-Way SOS Rescue Response (Help on the way!)
    PKT_TYPE_SOS_CANCEL     = 0x09,  // SOS Cancelled / Resolved broadcast
    PKT_TYPE_SILENT_CANCEL  = 0x0A,  // §10.4 Duress / Silent-Cancel Code (coercion safety)
    PKT_TYPE_RESCUE_LOCK    = 0x0B,  // §10.5 Multi-Node Rescue Swarm Claim-and-Lock token
    PKT_TYPE_CHECKIN_PROMPT = 0x0C,  // §10.3 Dead-Man's-Switch / Passive Check-In Prompt
    PKT_TYPE_CHECKIN_ACK    = 0x0D,  // §10.3 Passive Check-In User Acknowledgment
    PKT_TYPE_SAFE_CHECKIN   = 0x0E   // Active 'I am Safe & OK' Double-Tap Check-In Ping
};

enum PacketPriority : uint8_t {
    PRIORITY_BACKGROUND   = 0x00,    // Low-priority status/telemetry
    PRIORITY_NORMAL       = 0x01,    // Regular chat & background pings
    PRIORITY_HIGH         = 0x02,    // Direct messages / ACKs / Check-in warnings
    PRIORITY_EMERGENCY    = 0x03     // SOS Alerts (Preempts all traffic instantly)
};

enum GpsSource : uint8_t {
    GPS_SOURCE_NONE       = 0x00,  // No fix available
    GPS_SOURCE_NODE       = 0x01,  // Hardware NEO-6M live lock
    GPS_SOURCE_PHONE      = 0x02,  // Fallback location from paired smartphone
    GPS_SOURCE_LAST_KNOWN = 0x03   // Stale last known coordinates
};

// =============================================================================
// EMERGENCY STATE MACHINE & RISK CLASSIFICATION
// =============================================================================
enum EmergencyLifecycleState : uint8_t {
    STATE_NORMAL          = 0x00,  // Normal idle state
    STATE_VALIDATING      = 0x01,  // 3-second tactile hold / cancellation grace period
    STATE_SOS_GENERATED   = 0x02,  // Actively broadcasting SOS beacon
    STATE_SOS_RECEIVED    = 0x03,  // Remote node has acknowledged reception (Auto-ACK)
    STATE_RESCUE_ACCEPTED = 0x04,  // Human rescuer has actively confirmed response
    STATE_RESOLVED        = 0x05,  // Incident closed / marked safe
    STATE_SILENT_CANCEL   = 0x06   // Duress silent-cancel state (visible at LOW priority)
};

enum RiskTier : uint8_t {
    RISK_SAFE             = 0x00,  // 0 - 20
    RISK_LOW              = 0x01,  // 21 - 40
    RISK_MEDIUM           = 0x02,  // 41 - 60
    RISK_HIGH             = 0x03,  // 61 - 80
    RISK_CRITICAL         = 0x04   // 81 - 100
};

// =============================================================================
// BINARY PACKET HEADER & STRUCT (~40 bytes header + payload)
// =============================================================================
#define MESH_MAGIC_BYTE 0x53 // 'S' for SOS Mesh

#pragma pack(push, 1)
struct MeshPacketHeader {
    uint8_t  magic;               // 0x53
    uint16_t packetId;            // Unique sequence ID (Monotonic counter)
    uint16_t senderId;            // Originating node ID (lower 16-bit MAC)
    uint16_t recipientId;         // Target node ID or 0xFFFF for broadcast
    uint8_t  packetType;          // PacketType enum
    uint8_t  priority;            // PacketPriority enum
    uint8_t  hopCount;            // Number of hops traversed so far
    uint8_t  maxHops;             // Maximum hops allowed (TTL)
    uint8_t  gpsSource;           // GpsSource enum
    int32_t  latitude;            // Scaled by 1e7 (e.g. 12.9716000 -> 129716000)
    int32_t  longitude;           // Scaled by 1e7 (e.g. 77.5946000 -> 775946000)
    uint8_t  batteryPercent;      // 0 to 100%
    uint8_t  riskScore;           // Edge AI Risk Score (0 - 100)
    uint8_t  confidenceScore;     // Emergency Confidence Score (0 - 100%)
    uint8_t  signalAnomalyScore;  // §10.1 RF Signal Fingerprinting Anomaly Score (0 - 100)
    uint16_t timeToReserveMins;   // §10.6 Predictive Battery Degradation: Mins to <5% Reserve
    uint16_t rescueLockToken;     // §10.5 Multi-Node Rescue Swarm Claim Lock Token
    uint8_t  lifecycleState;      // EmergencyLifecycleState enum
    uint8_t  retryCount;          // Number of retransmission attempts
    uint8_t  payloadLen;          // Length of trailing payload
};
#pragma pack(pop)

#define MAX_PAYLOAD_LEN 170
#define MAX_PACKET_SIZE (sizeof(MeshPacketHeader) + MAX_PAYLOAD_LEN)

struct MeshPacket {
    MeshPacketHeader header;
    uint8_t payload[MAX_PAYLOAD_LEN + 1]; // Null-terminated safe buffer
    int16_t rssi;                         // Reception signal strength (dBm)
    float   snr;                          // Signal to Noise Ratio (dB)
    uint32_t timestamp;                   // Local arrival timestamp
};

// =============================================================================
// PACKET BUILDER HELPER FUNCTIONS
// =============================================================================
inline void initPacket(MeshPacket &pkt, uint16_t seqId, uint16_t src, uint16_t dst, 
                       PacketType type, PacketPriority prio, uint8_t maxHops) {
    pkt.header.magic = MESH_MAGIC_BYTE;
    pkt.header.packetId = seqId;
    pkt.header.senderId = src;
    pkt.header.recipientId = dst;
    pkt.header.packetType = (uint8_t)type;
    pkt.header.priority = (uint8_t)prio;
    pkt.header.hopCount = 0;
    pkt.header.maxHops = maxHops;
    pkt.header.gpsSource = GPS_SOURCE_NONE;
    pkt.header.latitude = 0;
    pkt.header.longitude = 0;
    pkt.header.batteryPercent = 100;
    pkt.header.riskScore = 0;
    pkt.header.confidenceScore = 0;
    pkt.header.signalAnomalyScore = 0;
    pkt.header.timeToReserveMins = 720; // 12 hours nominal baseline
    pkt.header.rescueLockToken = 0;
    pkt.header.lifecycleState = (uint8_t)STATE_NORMAL;
    pkt.header.retryCount = 0;
    pkt.header.payloadLen = 0;
    memset(pkt.payload, 0, sizeof(pkt.payload));
    pkt.rssi = 0;
    pkt.snr = 0;
    pkt.timestamp = millis();
}

#endif // MESH_PROTOCOL_H
