#ifndef PRIORITY_QUEUE_H
#define PRIORITY_QUEUE_H

#include <Arduino.h>
#include "Config.h"
#include "MeshProtocol.h"

// =============================================================================
// DEDUPLICATION HASH BUFFER (Prevents Mesh Loops / Storms)
// =============================================================================
struct SeenPacket {
    uint16_t senderId;
    uint16_t packetId;
    uint32_t seenTime;
};

class DeduplicationTable {
private:
    SeenPacket _history[DEDUPLICATION_CACHE_SIZE];
    uint8_t _headIndex = 0;

public:
    DeduplicationTable() {
        for (int i = 0; i < DEDUPLICATION_CACHE_SIZE; i++) {
            _history[i] = {0, 0, 0};
        }
    }

    bool isDuplicate(uint16_t senderId, uint16_t packetId) {
        uint32_t now = millis();
        for (int i = 0; i < DEDUPLICATION_CACHE_SIZE; i++) {
            if (_history[i].senderId == senderId && _history[i].packetId == packetId) {
                // If found within expiry window, it is a duplicate
                if (now - _history[i].seenTime < STORE_FORWARD_EXPIRY_MS) {
                    return true;
                }
            }
        }
        // Not a duplicate -> record it
        _history[_headIndex].senderId = senderId;
        _history[_headIndex].packetId = packetId;
        _history[_headIndex].seenTime = now;
        _headIndex = (_headIndex + 1) % DEDUPLICATION_CACHE_SIZE;
        return false;
    }
};

// =============================================================================
// DUAL-PRIORITY PREEMPTION TRANSMIT QUEUE
// =============================================================================
class PriorityTxQueue {
private:
    MeshPacket _sosQueue[TX_QUEUE_SIZE_SOS];
    uint8_t _sosHead = 0;
    uint8_t _sosTail = 0;
    uint8_t _sosCount = 0;

    MeshPacket _normalQueue[TX_QUEUE_SIZE_NORMAL];
    uint8_t _normHead = 0;
    uint8_t _normTail = 0;
    uint8_t _normCount = 0;

public:
    PriorityTxQueue() {}

    // Enqueue with automatic priority sorting
    bool push(const MeshPacket &pkt) {
        if (pkt.header.priority == PRIORITY_EMERGENCY || 
            pkt.header.packetType == PKT_TYPE_SOS || 
            pkt.header.packetType == PKT_TYPE_SILENT_SOS) {
            
            // Push to emergency queue
            if (_sosCount >= TX_QUEUE_SIZE_SOS) {
                // Force overwrite oldest if emergency queue is somehow full
                _sosHead = (_sosHead + 1) % TX_QUEUE_SIZE_SOS;
                _sosCount--;
            }
            _sosQueue[_sosTail] = pkt;
            _sosTail = (_sosTail + 1) % TX_QUEUE_SIZE_SOS;
            _sosCount++;
            return true;
        } else {
            // Push to normal queue
            if (_normCount >= TX_QUEUE_SIZE_NORMAL) {
                return false; // Normal queue full, drop or backpressure
            }
            _normalQueue[_normTail] = pkt;
            _normTail = (_normTail + 1) % TX_QUEUE_SIZE_NORMAL;
            _normCount++;
            return true;
        }
    }

    bool hasPending() const {
        return (_sosCount > 0 || _normCount > 0);
    }

    bool hasEmergencyPending() const {
        return (_sosCount > 0);
    }

    // Always pops emergency SOS first (Preemption)
    bool pop(MeshPacket &outPkt) {
        if (_sosCount > 0) {
            outPkt = _sosQueue[_sosHead];
            _sosHead = (_sosHead + 1) % TX_QUEUE_SIZE_SOS;
            _sosCount--;
            return true;
        } else if (_normCount > 0) {
            outPkt = _normalQueue[_normHead];
            _normHead = (_normHead + 1) % TX_QUEUE_SIZE_NORMAL;
            _normCount--;
            return true;
        }
        return false;
    }

    void clear() {
        _sosHead = _sosTail = _sosCount = 0;
        _normHead = _normTail = _normCount = 0;
    }
};

#endif // PRIORITY_QUEUE_H
