class_name RaceStats
extends RefCounted

## The `race` module's own stat-id vocabulary (ADR 0062).
##
## Stat ids are free `StringName` constants, so this file exists to keep the
## module's own ids in one place instead of spelled as literals at every use.
##
## Every id here is a **stat** a provider contributes, never a mechanic. The
## liabilities a body plan carries — which paths it closes, what realm it can
## never pass — are read from `RaceDef` by `RaceGate` and deliberately have no
## stat behind them, because a gate that reads a stat can be satisfied by an item.

## Ordinal of the highest realm this body plan can reach. 0 when the race has no
## ceiling, so a ceiling-less body reads 0 and an actor's own realm ordinal is
## the only number a consumer needs. Bounded by the 30-step shared ladder.
const REALM_CEILING := &"race_realm_ceiling"
## Total authored lifespan in days. A number to plan a life around, never a
## countdown the module runs itself.
const LIFESPAN := &"race_lifespan"
## How many of `PathState.ALL` this body can still cultivate: 3 minus the closed
## paths. The single legible answer to "what can this character become".
const PATH_COUNT := &"race_path_count"
## How many element affinities the body was born with.
const AFFINITY_COUNT := &"race_affinity_count"
## How strongly this body asserts in a contested conception. Equal to the race's
## authored `dominance`; exposed so a lineage screen can rank pairings without
## loading the catalog.
const DOMINANCE := &"race_dominance"
## Share of a contested conception this body needs before it manifests at all.
const MANIFESTATION_THRESHOLD := &"race_manifestation_threshold"
