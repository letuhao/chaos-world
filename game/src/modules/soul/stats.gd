class_name SoulStats
extends RefCounted

## Stat ids owned by the `soul` module (ADR 0899). Three channels, one question each:
##
## - SOUL_INTEGRITY — the ceiling. Baseline `100.0` is `SoulState.DEFAULT_INTEGRITY`, so an
##   actor with no contributions keeps the shipped ceiling byte-for-byte; a contribution
##   RAISES the stored ceiling and never lowers it (a soul shrunk below a life it survived
##   would be a second death the rules did not ask for).
## - SOUL_RECOVERY — integrity per period WITHOUT an anchor. Baseline `0.0` means "no passive
##   recovery": `SoulApi.recover` refuses until content authors a rate, so nothing heals in a
##   way the shipped game never did.
## - SOUL_ANCHOR — anchor repair efficiency multiplier. Baseline `1.0` means `AnchorApi.repair`
##   restores exactly `repair_per_period * periods`, the amount it restored before this stat
##   existed.
##
## The three baselines are the ADR 0897 discipline: the stats are built so CONTENT and the
## future L1 primaries have a socket, and they read their shipped values until something
## writes one.
const SOUL_INTEGRITY := &"soul_integrity"
const SOUL_RECOVERY := &"soul_recovery"
const SOUL_ANCHOR := &"soul_anchor"

const BASELINES := {
	SOUL_INTEGRITY: 100.0,
	SOUL_RECOVERY: 0.0,
	SOUL_ANCHOR: 1.0,
}
