# ECU map (Toyota BZ5)

All CAN tx/rx pairs encountered, with role hypothesis and exploration status.

| TX | RX | Role (confirmed/hypothesized) | Status |
| -- | -- | ---- | ------ |
| 701 | 709 | Gateway / VCU #1 | not explored |
| 702 | 70A | Gateway (primary) | partially explored — see registry |
| 703 | 70B | Gateway / VCU #3 | not explored |
| 713 | 71B | Motor controller 1 | not explored — energy candidate |
| 714 | 71C | Motor controller 2 | not explored — energy candidate |
| 716 | 71E | Motor controller 3 | not explored |
| 717 | 71F | Motor controller 4 | not explored |
| 721 | 729 | Inverter / DC-DC 1 | not explored — DC-DC energy candidate |
| 722 | 72A | Inverter / DC-DC 2 | not explored — DC-DC energy candidate |
| 724 | 72C | Inverter / DC-DC 3 | not explored |
| 732 | 73A | Aux #1 | not explored — HVAC candidate |
| 740 | 748 | PDU / HV Junction | partially explored — vehicle speed confirmed |
| 744 | 74C | PDU 2 | not explored |
| 745 | 74D | PDU 3 | not explored |
| 746 | 74E | PDU 4 | not explored |
| 750-756 | 758-75E | BMS slaves 1-6 | not explored — pack current candidate |
| 757 | 75F | GPS | confirmed (see registry) |
| 760 | 768 | Aux #2 | not explored — HVAC candidate |
| 777 | 77F | Aux #3 | not explored — HVAC candidate |
| 782 | 78A | OBC (on-board charger) | listed in registry, DIDs TBD |
| 786 | 78E | Aux #4 | not explored — HVAC candidate |
| 790 | 798 | BMS master | confirmed, heavily explored |
| 791 | 799 | VCU | partially explored — cycle 001 swept 0x0001-0x00FF (51/255 DIDs with payload); cycle 002 planned for state-differential |
| 7E5 | 7ED | OBD compliance (UDS standard) | not explored — generic OBD2 PIDs only |
| 7F1 | 7F9 | Gateway #2 | not explored |

**Top hypothesis for energy investigation (Cycle 1 target)**: VCU (791)
is the central powertrain coordinator and must compute power, so it
likely also exposes pack current.

**Backup hypotheses for sequence**:
- Cycle 2: BMS (790) if Cycle 1 yields nothing
- Cycle 3: PDU (740) if Cycle 2 yields nothing
- Cycle 4+: scan aux ECUs (732, 760, 777, 786) for HVAC

**Out of scope (for now)**:
- BMS slaves (750-756) likely just per-module data, not aggregate
- Inverter/DC-DC group may surface in later cycles if we want to
  measure 12V auxiliary draw specifically
