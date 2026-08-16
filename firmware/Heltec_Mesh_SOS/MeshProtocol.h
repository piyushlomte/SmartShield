#ifndef MESH_PROTOCOL_H
#define MESH_PROTOCOL_H

#include <Arduino.h>

// =============================================================================
// PACKET TYPES & PRIORITY DEFINITIONS
// =============================================================================
enum PacketType : uint8_t {
    PKT_TYPE_CHAT         = 0x01,  // Text chat message
    PKT_TYPE_SOS          = 0x02,  // High priority emergency beacon
    PKT_TYPE_POSITION     = 0x03,  // Periodic GPS telemetry
    PKT_TYPE_ACK          = 0x04,  // Message delivery acknowledgement
    PKT_TYPE_HEALTH       = 0x05,  // Node battery, RSSI, telemetry report
    PKT_TYPE_FALLBACK_REQ = 0x06,  // Node requesting Phone GPS fallback coordinates
    PKT_TYPE_SILENT_SOS   = 0x07,  // Silent stealth emergency beacon
    PKT_TYPE_SOS_RESPONSE = 0x08,  // 2-Way SOS Rescue Response (Help on the way!)
    PKT_TYPE_SOS_CANCEL   = 0x09   // SOS Cancelled / Resolved broadcast
};

enum PacketPriority : uint8_t {
    PRIORITY_NORMAL    = 0x00,     // Regular chat & background telemetry
    PRIORITY_HIGH      = 0x01,     // Direct messages / ACKs
    PRIORITY_EMERGENCY = 0x02      // SOS Alerts (Preempts all traffic)
};

enum GpsSource : uint8_t {
    GPS_SOURCE_NONE       = 0x00,  // No fix available
    GPS_SOURCE_NODE       = 0x01,  // Hardware NEO-6M live lock
    GPS_SOURCE_PHONE      = 0x02,  // Fallback location from paired smartphone
    GPS_SOURCE_LAST_KNOWN = 0x03   // Stale last known coordinates
};

// =============================================================================
// BINARY PACKET HEADER & STRUCT (~32 bytes header + payload)
// =============================================================================
#define MESH_MAGIC_BYTE 0x53 // 'S' for SOS Mesh

#pragma pack(push, 1)
struct MeshPacketHeader {
    uint8_t  magic;          // 0x53
    uint16_t packetId;       // Unique sequence ID
    uint16_t senderId;       // Originating node ID (e.g. last 2 bytes of MAC)
    uint16_t recipientId;    // Target node ID or 0xFFFF for broadcast
    uint8_t  packetType;     // PacketType enum
    uint8_t  priority;       // PacketPriority enum
    uint8_t  hopCount;       // Number of hops traversed so far
    uint8_t  maxHops;        // Maximum hops allowed (TTL)
    uint8_t  gpsSource;      // GpsSource enum
    int32_t  latitude;       // Scaled by 1e7 (e.g. 12.9716000 -> 129716000)
    int32_t  longitude;      // Scaled by 1e7 (e.g. 77.5946000 -> 775946000)
    uint8_t  batteryPercent; // 0 to 100%
    uint8_t  payloadLen;     // Length of trailing payload
};
#pragma pack(pop)

#define MAX_PAYLOAD_LEN 180
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
    pkt.header.payloadLen = 0;
    memset(pkt.payload, 0, sizeof(pkt.payload));
    pkt.rssi = 0;
    pkt.snr = 0;
    pkt.timestamp = millis();
}

#endif // MESH_PROTOCOL_H
