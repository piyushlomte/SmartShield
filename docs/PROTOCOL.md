# Offline Mesh Network Protocol Specification

## 1. Frame Architecture

All over-the-air LoRa packets use a binary frame structure for minimal transmission time and maximum RF energy efficiency.

### Binary Header (32 Bytes)
```
+---------------+------------------+------------------+------------------+
| Magic (1B)    | Packet ID (2B)   | Sender ID (2B)   | Recipient ID (2B)|
| 0x53 ('S')    | 0x0001 - 0xFFFF  | 0x0001 - 0xFFFE  | 0xFFFF=Broadcast |
+---------------+------------------+------------------+------------------+
| Type (1B)     | Priority (1B)    | Hop Count (1B)   | Max Hops (1B)    |
| 0x01-0x07     | 0=Norm, 2=Emerg  | 0, 1, 2...       | TTL (default 4)  |
+---------------+------------------+------------------+------------------+
| GPS Source(1B)| Latitude (4B, Scaled 1e7)           | Longitude (4B)   |
| 0, 1, 2, 3    | e.g. 129716000                     | e.g. 775946000   |
+---------------+------------------+------------------+------------------+
| Battery (1B)  | Payload Len (1B) | Payload (0-180 Bytes)...            |
| 0-100%        | N                | Raw text, binary, or encrypted data |
+---------------+------------------+-------------------------------------+
```

### Packet Types
- `0x01 PKT_TYPE_CHAT`: Text message across mesh channel or direct node.
- `0x02 PKT_TYPE_SOS`: Emergency beacon with priority preemption.
- `0x03 PKT_TYPE_POSITION`: Regular background location beacon.
- `0x04 PKT_TYPE_ACK`: Delivery confirmation response.
- `0x05 PKT_TYPE_HEALTH`: Node battery, link quality, and hop statistics.
- `0x06 PKT_TYPE_FALLBACK_REQ`: Requests paired smartphone location.
- `0x07 PKT_TYPE_SILENT_SOS`: Stealth emergency beacon (OLED stays off).

---

## 2. BLE UART JSON Bridge Format

Communication between the ESP32-S3 Node and the Flutter App occurs over Nordic UART Service (`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`):

### Node -> Phone (Notify)
```json
// Incoming Emergency Alert
{
  "type": "SOS_ALERT",
  "sender": 4660,
  "lat": 12.971600,
  "lon": 77.594600,
  "gps_src": 1,
  "text": "Medical Emergency at Camp",
  "rssi": -85,
  "snr": 8.5,
  "hops": 1
}

// Incoming Chat Message
{
  "type": "CHAT_MSG",
  "sender": 4660,
  "dst": 65535,
  "msg": "We reached checkpoint Alpha",
  "rssi": -92,
  "snr": 6.0,
  "lat": 12.971500,
  "lon": 77.594200,
  "bat": 84
}
```

### Phone -> Node (Write)
```json
// Send Chat Message
{"cmd": "CHAT", "dst": 65535, "msg": "Understood, moving to Bravo."}

// Dispatch Emergency SOS
{"cmd": "SOS", "text": "Injured climber needing extraction", "silent": false}

// Push Phone GPS Fallback
{"cmd": "PHONE_GPS", "lat": 12.971650, "lon": 77.594620}

// Reconfigure LoRa Frequency
{"cmd": "SET_FREQ", "freq": 433.175}
```
