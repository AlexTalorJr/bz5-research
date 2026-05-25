# Cycle NNN — short title

**Date issued**: YYYY-MM-DD
**Hypothesis target**: what we're testing
**Prerequisite cycles**: list (or "none" for fresh start)

## Hypothesis

What I believe and why, in 2-5 short paragraphs.

## Predictions

If the hypothesis is correct, we expect to see:
- [specific observable A]
- [specific observable B]

If the hypothesis is wrong but the alternative is X, we instead expect:
- [specific observable that distinguishes X]

## Experiment

Concrete command to issue. JSON in `command.json` is canonical;
this section explains *why* the parameters are chosen.

## Branching plan

| Outcome | Implication | Next cycle direction |
| ------- | ----------- | -------------------- |
| A | ... | ... |
| B | ... | ... |
| C (errors / no data) | ... | halt; ask owner |

## Constraints / prerequisites

What must be true for this experiment to be valid:
- Car state required
- BLE prerequisites
- Anything Friend 2 must verify before executing
