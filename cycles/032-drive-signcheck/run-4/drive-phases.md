# Run-4 drive phases (owner report)
~3-5 full-throttle accelerations + maximum-regen braking (full accelerator, then brake to max regen; not every cycle clean, but several were). Best high-current window of the cycle.
Session 21 / csid 10 / 1385 entries / exit=cancelled / ~600s.
Anomaly: 740/0023 + 740/0022 returned a STATIC value all run (0x46CB / 0x4657) while 740/0008 stayed live — PDU 740 sub-DIDs look cached/frozen this run. The signed zero-crossing for 740/0023 is from run-3 (0x46CB..0xC64F), not here.
