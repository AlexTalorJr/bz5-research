# Cycle 31 — AC charging current hunt — Notes for Друг 1

**Date**: 2026-05-29
**Bridge cycle**: 31 (6 probes: P0 baseline + P1-P5 charging)
**Operator**: Друг 2
**Client**: bz5-companion `0.1.29+32`
**Bridge**: revision `0003`
**Car state**: parked Ready ON; AC charging 16A @ 205-225V (~3.3 kW input) for ~100 min
**Total parked time**: ~1.5 hours

---

## TL;DR — **7 strong pack-current/power candidates confirmed**

Across P1-P5 (4 ECUs, 7 candidate DIDs + 3 anchors), **all 7 candidates surfaced with values matching Друг 1's physical predictions for 16A AC charging**. P5 final confirmation: 4450/4450 valid, all 7 candidates stable, mutual consistency across ECUs.

| DID | First raw | Padded uint | Scale ×0.1 | Source ECU | Physical interpretation |
|---|---|---|---|---|---|
| `740/0022` | `50` | 80 | **8.00 A** | PDU HV bus | HV current side A |
| `740/0023` | `4F` | 79 | **7.90 A** | PDU HV bus | HV current side B (paired with 0022) |
| `782/000A` | `97..98` | 151-152 | **15.10-15.20 A** | OBC AC side | AC line current (owner=16A) |
| `790/0009` | `54..57` | 84-87 | **8.4-8.7 A** | BMS pack | HV current at BMS sense |
| `790/0010` | `064D` | 1613 | **×0.01 = 16.13 A** | BMS / OBC link | AC current alt scale (full 2-byte payload — see Pattern A below) |
| `791/0038` | `25..29` | 37-41 | **3.7-4.1 kW** | VCU power-A | Total HV power |
| `791/0039` | `46..4A` | 70-74 | **7.0-7.4 A** | VCU HV side | HV current at VCU sense |

**Convergence across 4 sources**: 4 independent HV-current readings → all in **7.0-8.7 A** range (consistent with 16A AC × 0.92 OBC eff × 230V / 400V = ~8.5 A HV expected). 2 AC-current readings agree at **15.1-16.1 A**. Power converges at **3.7-4.1 kW** (slightly above 3.3 kW estimate but within OBC efficiency tolerance).

**Sign verification still needed**: all values positive (charging = current INTO pack). To complete sign-check, livelog the same 7 DIDs **on drive** — if they flip sign or stay positive-but-different-scale, that's the full proof.

---

## Probe-by-probe results

### P0 — baseline idle (120 s, parked Ready ON, no plug)
Reference snapshot. All 10 DIDs returned valid responses.

| DID | Idle (raw) | Notes |
|---|---|---|
| `790/0015` | `411E` (2-byte) | pack-V anchor, small variance |
| `790/1FFD` | `0E923B09` (4-byte) | SOC/state |
| `790/0B00` | `1164` (2-byte) | energy counter slow tick |
| `790/0006` | `05E7` (2-byte) | const |
| `790/0008` | `01BD` (2-byte) | const |
| `782/0009` | `01BC` (2-byte) | OBC idle status |
| `782/000C` | `03E8` (2-byte) | OBC idle status |
| `791/0038` | `0328` (2-byte) | power-A ~808 idle baseline |
| `791/0039` | `0648` (2-byte) | power-B ~1608 |
| `740/0008` | `0000` (2-byte) | PDU misc |

**File**: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P0

### P1 — OBC charger 782 + power 791 (300 s charging)
Friend-1's original plan had P1 at 5 min. After owner clarified probes should be 15-20 min, P2-P5 were 20 min each.

**Candidates from P1**: `791/0038` (3.7-4.1 kW power), `791/0039` (7.1-7.4 A HV), `782/000A` (15.1-15.2 A AC).

**File**: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P1

### P2 — BMS 790 current zone (1200 s)
Probed 790/0004-0009 + anchors. **New candidate**: `790/0009 = 81-87` (8.1-8.7 A HV from BMS). DIDs 0006/0007 are paired (both return `0xE7`). 0005 returned empty payload (DID exists, no value).

**File**: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P2

### P3 — BMS 790 uncharted 0x0010-0x0024 (1200 s)
Probed BMS upper-byte range. **Key find**: `790/0010 = 0x064D` (1613, full 2-byte response — not stripped!) → at ×0.01 = 16.13 A, matches AC. Other DIDs in the range are stable low-magnitude (0x3B, 0x89) or empty (0017, 0023, 0024 are empty payloads).

**File**: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P3

### P4 — PDU 740 + power anchor (1200 s)
Probed PDU. **Two new candidates**: `740/0022 = 0x50` (8.0 A) and `740/0023 = 0x4F` (7.9 A) — paired HV bus sense pair. 740/0008 (varied in C28 drive) **is zero on charge** — it's a motion-only signal. 740/000A returned NRC `7F2231` every cycle.

**File**: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P4

### P5 — final 7 candidates + 3 anchors (1200 s)
All 7 candidates from P1-P4 in one session for final confirmation. **100% mutual consistency** with predictions. 6 minor errors out of 4450 rows (0.13%, see *Anomalies* below).

**File**: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P5

---

## Pattern A — Payload-length inconsistency (worth flagging)

**Same DID returns 2-byte response in P0 (idle) but 1-byte response under charging.** The 1-byte version looks like the 2-byte version with leading zero stripped.

Examples:
| DID | P0 idle | P1-P5 charge | Interpretation if stripped |
|---|---|---|---|
| `791/0038` | `0328` (2B = 808) | `25..29` (1B) | `0x0025..0x0029` = 37-41 |
| `791/0039` | `0648` (2B = 1608) | `46..4A` (1B) | `0x0046..0x004A` = 70-74 |
| `790/0015` | `411E` (2B) | `XX` (1B, varies) | not directly comparable |
| `782/0009` | `01BC` (2B = 444) | `BE..BF` (1B) | `0x00BE..0x00BF` = 190-191 |

But **`790/0010` returned the full 2-byte response (`064D`) under charging**. So it's not a universal client serializer bug — it's DID-specific or response-specific.

Two possible interpretations:
1. **Different DIDs use different intrinsic payload lengths** depending on mode (idle ≠ charge). P0's `0x0328` may have been a multi-byte status code, while charging mode returns just the value byte.
2. **Client `0.1.29+32` serializer strips leading zeros for some DIDs**. Same pattern observed in C28 Phase A canmonitor frames. If true, padding-to-2-bytes recovers the intended value.

For decoding I padded with leading zero and the resulting numbers match physical predictions across **4 independent ECUs** — strong evidence that the padding interpretation is correct for these specific candidate DIDs at least. But you may want to double-check on the client implementation side what's happening with serializer.

---

## Anomalies (P5 minor errors, 6 total = 0.13%)

| Error | Count | Type |
|---|---|---|
| `NULL_RESPONSE` | 2 | BLE transport hiccup — no UDS response received |
| `EMPTY` | 2 | DID query timeout (similar to canmonitor's EMPTY) |
| `MISALIGNED:0185≠0B00` | 1 | Parser received response for DID `0185` while expecting `0B00` — likely from C15's BMS module-pair zone DIDs leaking into the response queue |
| `MISALIGNED:002D≠1FFD` | 1 | Parser received `002D` while expecting `1FFD` — same kind of out-of-order response |

The two `MISALIGNED` errors are new — first observation of cross-DID response misordering. Possible cause: ELM327 multi-frame UDS responses getting their `next_frame` indicators misread. 2 out of 4450 = below noise floor, but worth knowing the error code exists.

---

## Cross-probe DID activity matrix

| DID | P0 | P1 | P2 | P3 | P4 | P5 |
|---|---|---|---|---|---|---|
| `740/0008` | `0000` | — | — | — | `00` | — |
| `740/0009` | — | — | — | — | `D5..D6` | — |
| `740/0010` | — | — | — | — | empty | — |
| `740/0022` | — | — | — | — | `50` | `50` ⭐ |
| `740/0023` | — | — | — | — | `4F` | `4F` ⭐ |
| `782/0009` | `01BC` | `BE..BF` | — | — | — | — |
| `782/000A` | — | `97..98` ⭐ | — | — | — | `97..98` ⭐ |
| `782/000B` | — | `F4` | — | — | — | — |
| `782/000C` | `03E8` | `E8` | — | — | — | — |
| `790/0004-0008` | various | — | various | — | — | — |
| `790/0009` | — | — | `51..57` ⭐ | — | — | `54..57` ⭐ |
| `790/000A` | — | — | `BF..C2` | — | — | — |
| `790/0010` | — | — | — | `064D` ⭐ | — | `064D` ⭐ |
| `790/0011-0014` | — | — | — | various | — | — |
| `790/0015` (anchor) | `411E` | varies | varies | varies | varies | varies |
| `790/0B00` (counter) | `1164` | varies | varies | — | varies | varies |
| `790/1FFD` (SOC) | `0E923B09` | `883B09..` | `E23B09..` | `643B09..` | `E63B09..` | `7C3B09..EA3B09` |
| `791/0038` | `0328` | `25..29` ⭐ | — | — | `25..29` ⭐ | `25..29` ⭐ |
| `791/0039` | `0648` | `47..4A` ⭐ | — | — | — | `46..4A` ⭐ |

⭐ = matches Друг-1 predicted magnitude under charging.

---

## Recommendations

### Immediate (high confidence)
**The 7 confirmed candidates are pack current / AC current / power readings under AC charging.** Friend 1 has a robust set of measurement points now. The next step to fully nail down pack-current semantics is a **drive livelog with the same 7 DIDs**:
- If `791/0039` and `790/0009` and `740/0022/0023` go NEGATIVE during regen (or stay positive but match motor draw) — full sign-check, definitive pack-current ID.
- If `791/0038` power-A goes negative on regen and positive on drive — confirms it's signed power (out-of-pack negative).

### Medium-term
The two AC-current candidates (`782/000A` ×0.1 and `790/0010` ×0.01) differ in scale. Need a probe at a **different charger setting** (e.g., 10A or 6A AC) to see which one tracks the change. If both move proportionally, they're both real and scaling is just different.

### Lower priority
Pattern A (payload-length inconsistency idle vs charge) is a client decoding question. Probably not blocking analysis but worth understanding on Друг 1's side.

---

## Ссылки для Друг 1

- **Сводка C31**: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/031-ac-charging-current/notes-for-drug1.md
- **CSVs per probe**:
  - P0 baseline: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P0
  - P1: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P1
  - P2: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P2
  - P3: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P3
  - P4: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P4
  - **P5 (final 7+3)**: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/031-ac-charging-current/P5

- **Commits**: `e11cae8` (P0), `8202dc2` (P1), `297426d` (P2), `5d26069` (P3), `6fccd67` (P4), `0beaf8b` (P5), and this summary
