# Patent & Technical Innovation Reference

## Summary of Novel Mechanisms

### 1. Dual-Queue Preemption Engine for Mesh Radio Traffic
- **Problem**: Standard LoRa mesh protocols (like vanilla Meshtastic or RadioHead mesh) treat all incoming and outbound packets in a FIFO queue or basic channel-access backoff. During high chat or telemetry traffic, an emergency alert can suffer from queue latency or collision backoff.
- **Novelty**: Firmware implements a hardware/software dual-priority interrupt queue with zero-backoff preemption. When an emergency frame (`PKT_TYPE_SOS` or `PKT_TYPE_SILENT_SOS`) is enqueued, it instantly interrupts pending lower-priority frames, bypasses standard CSMA backoff windows, and commands intermediate nodes to drop regular packet forwarding until the SOS hop chain is satisfied.

### 2. Dual-Source Redundant GPS Arbitration with Telemetry Provenance Tagging
- **Problem**: GPS hardware modules (e.g. NEO-6M) frequently suffer from signal blockage under dense forest canopies, indoor canyons, or cold-start timeouts (27–45s). If an emergency occurs during GPS loss, devices fail to transmit accurate location data.
- **Novelty**: A 3-tiered location fallback engine with cryptographic telemetry provenance tags:
  1. Primary: Autonomous Hardware GPS (lowest power, independent of smartphone).
  2. Secondary: Paired smartphone GNSS/network location injected over Bluetooth Low Energy upon hardware timeout expiration (<20s).
  3. Tertiary: Timestamped last-known coordinate buffer.
  Every transmitted frame embeds a `GpsSource` provenance flag (`GPS_NODE`, `GPS_PHONE`, `GPS_LAST_KNOWN`), allowing search & rescue operators to distinguish between real-time lock and approximate positions.

### 3. Covert Multi-Tap Emergency Trigger & Rhythmic Haptic S&R Acoustic Beaconing
- **Novelty**: A dual-action capacitive sensor decoder that discriminates between standard long-press emergencies (accompanied by high-visibility OLED strobe and continuous haptic pulse) and stealth multi-tap sequences (disabling all on-device visual indicators while broadcasting encrypted stealth packets). Once activated, the node emits periodic rhythmic vibration harmonics that can be detected by tactile search teams in zero-visibility scenarios.
