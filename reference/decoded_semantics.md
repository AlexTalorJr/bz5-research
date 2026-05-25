# Decoded semantics

Long-form writeups for DIDs whose decoding required multiple cycles
or non-obvious reasoning to confirm. One entry per DID, in `## ECU/DID — name` format.

(Empty at bootstrap; will accumulate as cycles confirm new DIDs.)

---

## Template for new entry

### ECU/DID — short name

**First observed**: Cycle NNN
**Confirmed**: Cycle NNN (same or different from first observed)

**Raw format**: byte count, signed/unsigned, byte order if non-trivial.

**Decoding**: how raw bytes become the meaningful value. Include the
formula and any scale/offset.

**Semantics**: what the decoded value represents in physical units,
and how it relates to other DIDs.

**Confidence**: high / medium / low. What evidence supports the
decoding? What would falsify it?

**Cross-references**:
- Related DIDs on same ECU
- Related DIDs on other ECUs
- App code that consumes this DID (file:line)
