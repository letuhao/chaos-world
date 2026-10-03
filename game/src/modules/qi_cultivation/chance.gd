class_name QiChance
extends RefCounted

## The qi breakthrough roll, and the one rule that shapes it.
##
## `Stat.BREAKTHROUGH_CHANCE` is derived in core as
## `0.1 + comprehension * 0.01 + will * 0.005`, and `comprehension` IS this path's
## entry gate (`QiRealmSeed.comprehension_required`, authored up to 66). Reading it
## here meant the gate's own floor plus the dantian's quality drove the sum past the
## 0.95 clamp from the Immortal tier on, pinning every deep attempt at certainty:
## `_deviate` stopped firing, `QiTraining.recover` and all thirty authored
## `recovery_item`s became unspendable, and the recoverable-deviation loop was dead
## content on most of the ladder (ADR 0051's rule, which named qi as unfixed).
##
## So the roll reads the dantian and nothing else. Dantian quality is bounded twice
## — `Dantian.set_quality` clamps to 1.0 and `QiTraining.cultivate` stops at the next
## realm's own floor — so the sum cannot reach `MAX_CHANCE` at any realm, and
## circulating harder buys a sharper dantian rather than a certain breakthrough.

## Floor of the roll. Nothing may fall below it, so a deviation is always possible.
const MIN_CHANCE := 0.05
## Ceiling of the roll, and unreachable by any legal pre-state (asserted in
## `tests/modules/qi_cultivation/test_qi_breakthrough_chance.gd`).
const MAX_CHANCE := 0.95
## How much of the dantian's quality the roll can buy.
const QUALITY_TO_CHANCE := 0.5


static func of(dantian: Dantian) -> float:
	if dantian == null:
		return MIN_CHANCE
	return clampf(MIN_CHANCE + dantian.quality * QUALITY_TO_CHANCE, MIN_CHANCE, MAX_CHANCE)
