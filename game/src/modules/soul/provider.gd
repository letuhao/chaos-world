class_name SoulProvider
extends StatProvider

## Contributes the soul block's three channels at their NEUTRAL baselines (ADR 0899):
## `soul_integrity` 100, `soul_recovery` 0, `soul_anchor` 1.0. They are constants rather than
## formulas on purpose — a formula here would move every existing soul's ceiling or repair
## amount the day it changed, and the point of the block is that the sockets exist before
## anything writes them. L1 primaries and content are the writers.


func contribute(_context: StatContext) -> Dictionary:
	return SoulStats.BASELINES.duplicate()
