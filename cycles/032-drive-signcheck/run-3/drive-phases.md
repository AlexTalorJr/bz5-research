# Run-3 drive phases (owner report)

- Phase 1: first accel + braking — not cleanly to spec.
- Phase 2: better separation.
- Phase 3: **sharp reference accel + regen** — cleanest signed/byte-loss window.

Session 20 / csid 9 / 1079 entries / exit=cancelled / ~600s.

## Quick byte-loss + sign read (run-3 only)
- Pattern A (byte loss): NOT present. 791/0039 = 108/108 two-byte, MSB up to 0x0E; 790/0009 MSB up to 0x1E, all two-byte; zero 1-byte samples on any current DID.
- Sign: 740/0023 crosses zero as signed int16 (0x46CB=+18123 .. 0xC64F=-14769) -> bidirectional pack current. 790/0009/0038/0039 vary widely but stay positive raw (offset-encoded). 
- 790/0010 = 3-byte, near-constant 0x069D under drive (AC-side current, inactive off-charge).
- 740/0022 = flat ~0x465x (not current). 790/0015 pack-V 11 empty responses + 97 valid.
