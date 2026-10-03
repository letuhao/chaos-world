class_name ClanStats
extends RefCounted

## The `clan` module's own stat-id vocabulary (ADR 0064).
##
## Stat ids are free `StringName` constants, so this file exists to keep the module's
## own ids in one place instead of spelled as literals at every use.
##
## ## Every id here is a non-combat SUMMARY. That is the constraint, not a detail.
##
## A clan grants recognition, never power, so none of these may be an id the shared
## derived pipeline treats as a combat value — no `attack_*`, no `defense_*`, no
## `max_health`, no base attribute. Membership is a social position; the numbers below
## let a reputation system read it, and `ClanGate` reads the actual gates from the
## LEDGER rather than from a stat, because a gate that reads a stat can be satisfied
## by an item.

## How much standing this member has earned. A recognition currency, not power: it
## composes against reputation features, and nothing in combat reads it.
const STANDING := &"clan_standing"
## Ordinal of the position held in the clan's ladder, 0 at the entry rank. An ordinal
## in a social ladder — not an experience level, and not anything a fight consults.
const RANK_INDEX := &"clan_rank_index"
## How many published standing bands this member has cleared, plus one so an outsider
## reads 0 rather than colliding with the lowest band. "How much of the ladder".
const BAND_INDEX := &"clan_band_index"
## Bounded index of the published `patronage` and `duty` terms on both sides. A COUNT
## of terms rather than a sum of authored values, so content can publish obligations
## without hand-authoring a dial. Nothing is enforced: the clan publishes the terms.
const PATRONAGE_TIER := &"clan_patronage_tier"
## How many rival houses this member's clan names. A measure of how contested their
## recognition is, and the kind of number a diplomatic screen sorts by.
const RIVAL_COUNT := &"clan_rival_count"
