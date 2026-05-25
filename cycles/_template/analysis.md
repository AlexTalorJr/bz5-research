# Cycle NNN — Analysis

**Date analyzed**: YYYY-MM-DD
**Data sources**: list raw/ files consumed

## Observations

What the data actually shows, before interpretation. Count of responding
DIDs, error rate, anomalies vs predictions. Stick to facts.

## Interpretation

What the observations mean. Distinguish "high confidence" (one
observation matches one expected pattern unambiguously) from
"speculative" (we'd need a follow-up cycle to confirm).

## Candidate DIDs

Table of DIDs that look interesting. Columns:
- ECU
- DID
- Byte count
- Raw value range observed
- Decoded guess (with confidence: confirmed / likely / speculative)
- Rationale

## Anti-matches

DIDs that we suspected but the data rules out. Important to record so
future cycles don't re-investigate the same dead ends.

## Branching decision

Which branch (from hypothesis.md "Branching plan") we're taking, and why.

## Next cycle

Short sentence pointing to `next.md` for the seed of Cycle NNN+1.
