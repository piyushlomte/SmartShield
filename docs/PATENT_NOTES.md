# AI-SOS Mesh Intelligence System
## Technical Disclosure & Engineering Report (Patent-Preparation Draft)

**Status:** Internal engineering disclosure for prior-art search and patent-attorney review. Not a legal document. Nothing in this report constitutes legal advice on patentability, novelty, or freedom-to-operate. Before filing, engage a licensed patent attorney and commission a formal prior-art search.

---

### Abstract / Core Invention Concept

> **A self-authenticating, priority-aware, store-and-forward emergency communication system that dynamically determines emergency severity, transmission priority, acknowledgement state, and rescue status, using only two LoRa/BLE nodes and a smartphone.**

This one-sentence statement is the anchor for the entire disclosure and is the recommended basis for the eventual patent abstract. Every mechanism in Sections 5–6 and 10 exists to make one of its five claimed properties concrete and implementable:

| Property in Abstract | Implementing Mechanism(s) |
| :--- | :--- |
| **Self-authenticating** | §5.9 Security Layer — per-packet Device ID + Sequence Number + Nonce + Authentication Tag, replay protection, challenge/response pairing |
| **Priority-aware** | §5.5 Priority-Aware Transmission Scheduler; §10.2 Risk-Driven SF/Bandwidth Switching |
| **Store-and-forward** | §5.8 Store-and-Forward, Sequence-Aware Sync (route history, hop count, TTL, differential resync); §5.14 Offline Mesh Chat (shared-substrate messaging) |
| **Dynamically determines emergency severity** | §5.2 Risk & Confidence Scoring; §10.1 RF Signal Fingerprinting; §10.6 Predictive Battery-Health Model |
| **Transmission priority** | §5.5 Priority-Aware Scheduler; §5.6 Adaptive Retry & Link-Aware Escalation |
| **Acknowledgement state** | §5.1 Emergency State Machine (TX → ACK? → escalate); §5.7 Rescue Acknowledgement Protocol |
| **Rescue status** | §5.7 Four-Stage Lifecycle (GENERATED → RECEIVED → ACCEPTED → RESOLVED); §10.5 Rescue-Claim Locking |
| **Only two LoRa/BLE nodes and a smartphone** | §4 System Architecture — no hardware beyond Node A, Node B, and the companion app; protocol is forward-compatible with more nodes (§5.8) but requires none |

---

## 0. How to Use This Report

This document is structured the way a patent attorney typically wants to receive an invention disclosure: problem $\rightarrow$ prior art gap $\rightarrow$ system architecture $\rightarrow$ detailed mechanisms $\rightarrow$ candidate points of novelty $\rightarrow$ draft claim language (informal) $\rightarrow$ differentiation table $\rightarrow$ build plan.

Sections 1–9 are the “report.” Section 10 adds **new features beyond the original concept**, chosen specifically because they add software/protocol-level novelty without changing your hardware bill of materials.

**Hardware BOM:** $2\times$ Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262), $1\times$ GPS module (Node A only), push-button, vibration motor, LiPo battery, SSD1306 OLED — no new sensors.

---

## 1. Field of the Invention

The invention relates to portable, infrastructure-independent emergency communication systems, and more specifically to a method and system for converting a raw emergency trigger (button press) into a confidence-weighted, prioritized, cryptographically authenticated emergency state that is adaptively transmitted, retried, escalated, and synchronized across a long-range low-power radio link (LoRa) and a companion mobile application, without dependency on cellular, Wi-Fi, or internet infrastructure.

---

## 2. Background / Problem Statement

Existing personal-safety LoRa/BLE devices typically implement a flat model:
$$\text{Button press} \longrightarrow \text{Fixed-format packet} \longrightarrow \text{LoRa broadcast} \longrightarrow \text{Local alert}$$

This model has several known limitations common across commercial and open-source SOS trackers:
1. **No severity differentiation** — every button press is treated identically, so accidental presses generate the same urgency as genuine emergencies.
2. **No acknowledgement-aware retry logic** — packets are usually retransmitted on a fixed timer regardless of link quality or whether the counterpart node received them.
3. **No persistent, tamper-evident incident record** — most devices show a live status but don’t retain a verifiable timeline usable as evidence after the fact.
4. **Phone-dependent architecture** — many designs route all logic through the paired smartphone, so the emergency function degrades if BLE disconnects.
5. **No replay protection** — packets are frequently unauthenticated or only checksum-protected, making them susceptible to spoofing or replay.
6. **Static power behavior** — battery state is displayed but not used to actively reconfigure system behavior to preserve emergency capability.

The gap this system fills is not in the individual components (LoRa, GPS, BLE, buttons — all pre-existing, publicly available technologies) but in the **specific orchestration and state-management mechanism** that binds them together into a self-authenticating, priority-aware, store-and-forward emergency protocol.

---

## 3. Summary of the Invention

A two-node (extensible to N-node) emergency mesh system in which:
- A local event engine on Node A converts a physical trigger into a validated, confidence-scored emergency event.
- A risk/confidence engine classifies the event using only locally available telemetry (button pattern, GPS availability, battery, prior event history, link quality) — no additional sensors required.
- A secure, versioned packet format carries the emergency state, its risk/confidence values, and integrity/authentication data.
- A priority-aware transmission scheduler ensures emergency packets preempt non-emergency traffic (chat, telemetry, status) in the LoRa queue.
- An adaptive retry/escalation state machine changes retry cadence and packet priority based on acknowledgement status and observed link quality (RSSI/SNR), escalating severity if acknowledgement is delayed or absent.
- A four-stage emergency lifecycle (`GENERATED` $\rightarrow$ `RECEIVED` $\rightarrow$ `ACCEPTED` $\rightarrow$ `RESOLVED`) is maintained independently on both nodes and reconciled with the mobile application when connectivity is available, so the emergency function is not dependent on a continuous phone connection.
- A store-and-forward, sequence-numbered synchronization protocol allows the phone to resume from its last known sequence number rather than resyncing full history, reducing BLE traffic.
- An immutable, hash-chained incident journal records every state transition with a timestamp, enabling export of a tamper-evident “Emergency Incident Record” after the event resolves.
- A battery-aware operating-mode controller progressively strips non-essential radio activity as battery falls, explicitly reserving power for SOS/ACK-class traffic only, rather than merely displaying a battery percentage.

---

## 4. System Architecture

```
                    ┌──────────────────────────┐
                    │       MOBILE APP         │
                    │                          │
                    │ AI Emergency Engine      │
                    │ Offline Database (SQLite)│
                    │ Offline Map              │
                    │ Device Management        │
                    └────────────┬─────────────┘
                                 │ BLE (optional, not required for core function)
                                 ▼
                  ┌───────────────────────────┐
                  │        HELTEC NODE A      │
                  │ ESP32-S3 + SX1262 LoRa    │
                  │ GPS · SOS Button · Vibe   │
                  │ Battery · OLED            │
                  │ Local Event Engine        │
                  │ Risk/Confidence Engine    │
                  │ Packet Engine · Security  │
                  └─────────────┬─────────────┘
                                │ Authenticated LoRa
                                ▼
                  ┌───────────────────────────┐
                  │        HELTEC NODE B      │
                  │ ESP32-S3 + SX1262 LoRa    │
                  │ OLED · Vibe · Button      │
                  │ Battery                   │
                  │ Rescue Intelligence Engine│
                  │ ACK/Escalation Engine     │
                  │ Relay Engine (future mesh)│
                  └─────────────┬─────────────┘
                                │ BLE
                                ▼
                         RESCUE MOBILE
```

The ESP32-S3 provides BLE, ample GPIO/peripherals, hardware security primitives (AES, secure boot, HMAC, digital signatures), and vector instructions suited to lightweight edge inference — all used here without adding silicon beyond the stated BOM.

---

## 5. Core Technical Mechanisms

### 5.1 Emergency State Machine (primary novelty axis)
$$\text{NORMAL} \rightarrow \text{EVENT DETECTED} \rightarrow \text{EVENT VALIDATION} \rightarrow \text{RISK ESTIMATION} \rightarrow \text{EMERGENCY CLASSIFICATION} \rightarrow \text{TRANSMISSION PRIORITY} \rightarrow \text{SECURE PACKET CREATION} \rightarrow \text{LoRa TRANSMISSION} \rightarrow \text{ACKNOWLEDGEMENT} \rightarrow \text{RESCUE CONFIRMATION} \rightarrow \text{EVENT CLOSED}$$

**Failure branch:**
$$\text{TX} \rightarrow \text{NO ACK} \rightarrow \text{RETRY} \rightarrow \text{NO ACK} \rightarrow \text{ESCALATE} \rightarrow \text{HIGHER-PRIORITY RETRANSMISSION}$$

This is the central claimable mechanism: the transformation of a binary trigger into a **multi-stage, escalating, acknowledgement-gated state object**, rather than a single fire-and-forget message.

### 5.2 Risk & Confidence Scoring (explainable, deterministic v1)
Two independent scalar outputs:
- **RISK SCORE ($0–100$):**
  - SOS pressed: $+40$
  - No cancellation: $+15$
  - GPS available: $+10$
  - Repeated SOS: $+15$
  - No ACK: $+10$
  - Comms failure: $+10$
  - *Bands:* $0–20$ `SAFE` $\cdot$ $21–40$ `LOW` $\cdot$ $41–60$ `MEDIUM` $\cdot$ $61–80$ `HIGH` $\cdot$ $81–100$ `CRITICAL`.
- **CONFIDENCE SCORE ($0–100\%$):** Sensor/data completeness, Consistency across inputs, Repeat-event correlation.

### 5.3 SOS Validation & Confidence Escalation
$$\text{Button pressed} \rightarrow \text{3s validation window} \rightarrow \text{vibration confirmation} \rightarrow \text{user cancels?} \xrightarrow{\text{YES}} \text{SAFE} \quad / \quad \xrightarrow{\text{NO}} \text{EMERGENCY}$$
$$\text{Repeated activation within window} \rightarrow \text{confidence increases} \rightarrow \text{CRITICAL}$$

### 5.4 Emergency State Packet (structured, versioned)
- **HEADER:** `Device ID` $\cdot$ `Message ID` $\cdot$ `Sequence No` $\cdot$ `Packet Type` $\cdot$ `Priority` $\cdot$ `Risk Score` $\cdot$ `Confidence` $\cdot$ `Hop Count` $\cdot$ `TTL` $\cdot$ `Timestamp`
- **DATA:** `Latitude` $\cdot$ `Longitude` $\cdot$ `GPS Accuracy` $\cdot$ `Battery` $\cdot$ `Event State` $\cdot$ `Signal Anomaly Score` $\cdot$ `Time-to-Reserve` $\cdot$ `Rescue Lock Token`
- **SECURITY:** `Authentication Tag` $\cdot$ `Integrity/CRC` $\cdot$ `Nonce`

### 5.5 Priority-Aware Transmission Scheduler
Emergency-class packets preempt the LoRa TX queue ahead of chat, telemetry, and status traffic:
$$\text{Queue before SOS: } [\text{CHAT}, \text{BATTERY}, \text{STATUS}] \quad\longrightarrow\quad \text{Queue after SOS: } [\text{SOS}, \text{CHAT}, \text{BATTERY}, \text{STATUS}]$$

### 5.6 Adaptive Retry & Link-Aware Escalation
$$\text{TX} \rightarrow \text{ACK?} \xrightarrow{\text{YES}} \text{DONE}$$
$$\xrightarrow{\text{NO}} \text{analyze RSSI/SNR} \rightarrow \text{adjust retry interval} \rightarrow \text{RETRY}$$
- Strong RSSI $\rightarrow$ short interval ($4\text{s}$).
- Weak RSSI $\rightarrow$ longer interval ($7\text{s}$).
- Repeated failure $\rightarrow$ mark `COMMUNICATION FAILURE`, escalate priority to `CRITICAL`.

### 5.7 Rescue Acknowledgement Protocol & Four-Stage Lifecycle
$$\text{SOS\_GENERATED} \rightarrow \text{SOS\_RECEIVED} \rightarrow \text{RESCUE\_ACCEPTED} \rightarrow \text{USER\_SAFE/RESOLVED}$$
Node B operator can explicitly **ACCEPT SOS**, propagating `RESCUE_ACCEPTED` back to Node A and the origin phone — turning a one-way alert into a bidirectional, confirmable rescue workflow.

### 5.8 Store-and-Forward, Sequence-Aware Sync
Protocol fields (`Origin ID`, `Destination ID`, `Message ID`, `Hop Count`, `TTL`, `Route history`) support future multi-hop relay ($A \rightarrow B \rightarrow C \rightarrow D$) without breaking changes. Phone resync uses differential sequence sync:
$$\text{Phone sends: } \text{LastSeq} = 145 \quad\longrightarrow\quad \text{Device sends: } [146 \dots 152] \text{ (only the delta)}$$

### 5.9 Security Layer
- Device pairing via challenge/response with explicit user confirmation.
- Per-packet `Device ID` + `Sequence Number` + `Nonce` + `Authentication Tag` $\rightarrow$ replay protection.
- Authenticated-encryption primitives (AES-GCM / HMAC) and ESP32-S3 hardware cryptographic accelerators.

### 5.10 Battery-Aware Emergency Power Reserve
- **$100–20\%$:** `NORMAL`
- **$20–10\%$:** `POWER SAVING` (reduce background/status traffic)
- **$10–5\%$:** `EMERGENCY RESERVE`
- **$<5\%$:** `SOS-ONLY PRIORITY MODE` (SOS + ACK + essential status only)

### 5.11 Non-Visual Communication Channel (Vibration Language)
- $1\text{ pulse} = \text{normal}$
- $2\text{ pulses} = \text{warning}$
- $3\text{ pulses} = \text{SOS received}$
- $\text{long pulse} = \text{critical}$
- $\text{long-short-long} = \text{rescue accepted}$

### 5.12 GPS & Location Confidence (not raw GPS=Y/N)
Location confidence is computed from fix availability, satellite quality, position age, and accuracy — surfaced as a percentage with staleness warnings.

### 5.13 Immutable Incident Journal / Evidence Mode
Every state transition is appended to a local, sequence-numbered, hash-chained journal (each entry references the SHA-256 hash of the prior entry), producing a tamper-evident incident timeline exportable as an “Emergency Incident Record”.

### 5.14 Offline Mesh Chat / Secondary Messaging Channel
Chat is defined as a strictly lower-priority instance of the same authenticated packet class, sharing one scheduler, one retry/ACK engine, one sync protocol, and one security layer as the emergency channel.

---

## 6. AI Algorithms & Datasets (2-Tier Edge + Mobile Architecture)

```
┌────────────────────────────────────────────────────────┐
│                      TIER 1: EDGE AI                   │
│                   (Embedded on ESP32-S3)               │
│                                                        │
│ 1. Explainable Multi-Criteria Decision Fusion (MCDF)   │
│ 2. Heuristic Context Risk Engine (0–100 Score)         │
│ 3. Link-Adaptive RF Backoff Scheduler (SNR/RSSI)       │
└───────────────────────────┬────────────────────────────┘
                            │ BLE Sync
                            ▼
┌────────────────────────────────────────────────────────┐
│                     TIER 2: MOBILE AI                  │
│                   (Flutter On-Device AI)               │
│                                                        │
│ 1. 3-Phase Kinematic Fall & Inactivity Classifier      │
│ 2. Sliding-Window Variance Thresholding (SVM / RF)     │
│ 3. Natural Language Emergency Explainability Engine    │
└────────────────────────────────────────────────────────┘
```

### 6.1 Tier 1 — Explainable Multi-Criteria Decision Fusion (MCDF)
$$\text{Risk Score} = \sum w_i \cdot \phi_i(x_i) = w_{\text{btn}} S_{\text{btn}} + w_{\text{rep}} S_{\text{rep}} + w_{\text{ack}} S_{\text{no\_ack}} + w_{\text{rf}} S_{\text{snr}} + w_{\text{bat}} S_{\text{bat}}$$

### 6.2 Tier 2 — 3-Phase Kinematic Fall & Inactivity Anomaly Classifier
- **Phase 1 (Free-fall):** Total G-force $r(t) = \sqrt{x^2+y^2+z^2} < 0.35\text{g}$ for $\Delta t \in [100\text{ms}, 400\text{ms}]$.
- **Phase 2 (Impact):** Impact spike $r(t) > 2.25\text{g}$.
- **Phase 3 (Post-impact Inactivity):** Motion variance $\text{Var}(r) < 0.25\text{ m}^2/\text{s}^4$ over 2.5s window.

### 6.3 Tier 1 — Link-Adaptive RF Retry Scheduler (Dynamic QoS)
$$T_{\text{retry}} = \begin{cases} 4000\text{ ms}, & \text{if } SNR \ge +2\text{ dB} \text{ (good link — fast recovery)} \\ 7000\text{ ms}, & \text{if } -5\text{ dB} \le SNR < +2\text{ dB} \\ 11000\text{ ms} + (2000 \times N_{\text{retry}}), & \text{if } SNR < -5\text{ dB} \text{ (degraded/congested — anti-collision)} \end{cases}$$

### 6.4 Training & Validation Datasets
1. **SisFall Dataset** ($4,510$ trials, $38$ subjects, $19$ ADL $+ 15$ fall profiles, $200\text{ Hz}$).
2. **MobiFall Dataset** (Smartphone inertial sensor benchmark).
3. **UR Fall Detection (URFD)** (Accelerometer + depth camera ground truth).
4. **Custom AI-SOS Telemetry Matrix** (`mesh_sos.db` SQLite store).

---

## 7. Draft Points of Novelty (Informal — For Attorney Refinement)

1. A method of converting a manually triggered emergency signal into a **risk score and an independent confidence score**, and using the pair to select an escalation path.
2. A **priority-preemptive transmission scheduler** for a long-range radio link that re-orders mixed traffic queues based on dynamically computed emergency priority.
3. A **link-quality-adaptive retry algorithm** where retry interval and priority are functions of measured RSSI/SNR and acknowledgement history.
4. A **four-stage bidirectional emergency lifecycle** (`GENERATED` $\rightarrow$ `RECEIVED` $\rightarrow$ `ACCEPTED` $\rightarrow$ `RESOLVED`) maintained redundantly on two radio endpoints.
5. A **battery-state-gated packet class filter** that progressively restricts packet types as battery falls, explicitly reserving capacity for emergency transmissions.
6. A **hash-chained local incident journal** producing a tamper-evident exportable emergency record without cloud dependency.
7. A **differential sequence-number resynchronization method** between node and mobile app transmitting only the delta backlog.
8. A **two-tier, multi-trigger emergency inference architecture** (edge deterministic fusion + mobile kinematic classifier).
9. A **shared-substrate messaging architecture** where non-emergency chat rides the identical authenticated, priority-aware transport without dedicated subsystems.

---

## 8. Differentiation from Prior Art

| Metric / Capability | Conventional SOS Device | AI-SOS Mesh Intelligence System |
| :--- | :--- | :--- |
| **Trigger** | Button $\rightarrow$ alert | Event $\rightarrow$ validated, scored emergency state |
| **Transmission** | Single fixed-priority transmission | Priority-preemptive, adaptive-retry transmission |
| **Link Confidence** | Connected / disconnected | Numeric communication confidence from RSSI/SNR/ACK |
| **Workflow** | One-way alert | Four-stage bidirectional lifecycle with explicit rescue acceptance |
| **Location** | GPS present/absent | Location confidence score with staleness tracking & 3-tier provenance |
| **Battery** | Battery percentage display | Battery-gated emergency packet-class reservation |
| **Security** | Checksum or no authentication | Authenticated, replay-protected, sequence-numbered packets |
| **Architecture**| Phone-dependent | Node-resident state; phone reconciles opportunistically |
| **Forensics** | Live status only | Immutable, SHA-256 hash-chained, exportable incident record |

---

## 9. Documentation & Filing Recommendations

1. **Prior-art search first**: Search LoRa/LoRaWAN emergency-beacon patents, backcountry beacons, and LPWAN scheduling.
2. **Inventor's log**: Maintain dated design logs for all 51 mechanisms.
3. **Separate "AI" from rules engine**: Document deterministic MCDF distinctly from ML models.
4. **Cryptographic primitives**: Claim system use of authentication/nonces/sequences, not novel ciphers.
5. **Provisional filing**: File provisional application early to lock priority date.
6. **Working prototype**: Reduce to practice on Heltec V3 + Flutter companion app.

---

## 10. Additional Feature Proposals (§10.1 – §10.8)

### 10.1 RF Signal Fingerprinting for Situational Inference
Tracks sudden sustained signal attenuation ($>18\text{ dB}$ drop in $<40\text{s}$) consistent with burial, submersion, or cave-in, outputting a **Signal Anomaly Score** ($0-100$) into the Risk Engine.

### 10.2 Adaptive Physical-Layer Configuration (Risk-Driven SF/Bandwidth Switching)
Dynamically switches LoRa Spreading Factor: background uses higher SF (SF10), but upon HIGH/CRITICAL emergency, radio temporarily switches to faster SF7 to minimize latency for ACK handshakes, then reverts.

### 10.3 Dead-Man’s-Switch / Passive Check-In Mode
Prompts user with periodic vibration within a configurable window ($15/30/60\text{ min}$); missed check-in auto-generates a LOW/MEDIUM risk event that escalates if unaddressed.

### 10.4 Duress / Silent-Cancel Code
Distinct trigger pattern that cancels SOS on OLED without signaling "false alarm" to rescue side — logging a `SILENT_CANCEL` state held at LOW priority for rescue verification (coercion safety).

### 10.5 Multi-Node Rescue Swarm Coordination (Rescue-Claim Locking)
When a rescue node sends `RESCUE_ACCEPTED`, that claim is broadcast with a lock token so other listening nodes don't duplicate response and can be redirected to other concurrent incidents.

### 10.6 Predictive Battery-Health Degradation Model
Estimates `time-to-SOS-only-mode` (minutes remaining until $<5\%$ reserve) based on discharge velocity $\Delta V / \Delta t$ rather than raw static percentage.

### 10.7 Incident Journal Hash-Chain Anchoring (Export-Time Notarization)
Surfaces final cumulative SHA-256 hash anchor as an offline QR Code and alphanumeric fingerprint for tamper verification without blockchain or network connection.

### 10.8 Explainable Escalation Narratives
AI Assistant explicitly cites triggering mechanisms in natural language (e.g. *"Escalated to CRITICAL because: RSSI dropped 18dB in 40s (signal anomaly) AND ACK not received after 2 retries"*).

---

## 11. Consolidated Feature List (Original 43 + 8 New = 51)

1. **Emergency Intelligence (15):** Manual SOS $\cdot$ Silent SOS $\cdot$ Duress/silent-cancel code $\cdot$ SOS validation $\cdot$ Risk score $\cdot$ Confidence score $\cdot$ Signal-anomaly score $\cdot$ Emergency classification $\cdot$ Escalation $\cdot$ False-alarm cancellation $\cdot$ Emergency state machine $\cdot$ Dead-man’s-switch check-in $\cdot$ Rescue acceptance $\cdot$ Rescue-claim locking $\cdot$ Emergency resolution
2. **Communication (11):** Direct LoRa $\cdot$ Store-and-forward $\cdot$ Priority queue $\cdot$ Adaptive retry $\cdot$ Risk-driven SF/bandwidth switching $\cdot$ ACK/NACK $\cdot$ Duplicate suppression $\cdot$ TTL/hop-count/route history $\cdot$ Sequence numbers $\cdot$ Communication confidence $\cdot$ Offline operation
3. **Location (5):** GPS acquisition & confidence $\cdot$ Last-known location $\cdot$ Emergency location refresh $\cdot$ Offline map $\cdot$ Location history
4. **Mobile App (9):** BLE pairing $\cdot$ Offline database $\cdot$ Offline chat $\cdot$ SOS dashboard $\cdot$ Rescue dashboard $\cdot$ Mesh visualization $\cdot$ Incident history $\cdot$ Emergency Incident Record export with hash anchoring $\cdot$ AI Emergency Assistant with mechanism-linked explanations
5. **Power (4):** Battery monitoring $\cdot$ Emergency power reserve $\cdot$ SOS-only mode $\cdot$ Predictive battery-health degradation
6. **Security (4):** Authenticated pairing $\cdot$ Encrypted, authenticated payloads $\cdot$ Nonce/sequence replay protection $\cdot$ Security event logging
7. **Reliability (3):** Full self-test suite $\cdot$ Mesh health score $\cdot$ Cryptographic hash-chain verification

---

## 12. Bottom Line

> **“An offline, AI-assisted emergency-state-management system that converts a physical trigger into a confidence-weighted, escalating emergency state; transmits it over a priority-preemptive, link-adaptive long-range radio channel with authenticated, replay-protected packets; maintains a bidirectional acknowledgement/acceptance lifecycle independent of any continuous phone connection; and persists a tamper-evident incident record synchronized differentially with a companion application — all on a fixed two-node hardware platform with no additional sensors.”**
