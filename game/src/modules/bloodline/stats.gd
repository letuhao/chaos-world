class_name BloodlineStats
extends RefCounted

## The `bloodline` module's own stat-id vocabulary (ADR 0063).
##
## Stat ids are free `StringName` constants, so this file exists to keep the module's
## own ids in one place instead of spelled as literals at every use.
##
## Every id here is a **stat** a provider contributes, never a mechanic. Whether a
## lineage is awake is read from the ledger by `BloodlineGate`, deliberately with no
## stat behind it, because a gate that reads a stat can be satisfied by an item.

## How many distinct lineages this actor carries a concentration for. The single
## legible answer to "how much of an ancestry is this".
const LINEAGE_COUNT := &"bloodline_lineage_count"
## How many of those have crossed their authored awaken threshold.
const AWAKENED_COUNT := &"bloodline_awakened_count"
## Highest concentration carried, in `[0, 1]`. 0.0 when nothing is carried.
const PEAK_PURITY := &"bloodline_peak_purity"
## Mean concentration across every carried lineage, in `[0, 1]`. The dilution readout:
## two lineages at 0.9 score higher here than one lineage alone.
const MEAN_PURITY := &"bloodline_mean_purity"
## Bounded aggregate of every AWAKEN lineage's percent grants, in fractions. It reads
## what an awakened ancestry is currently worth, and is clamped so a broad or badly
## scaled lineage cannot dominate the shared stat pool.
const BLOODLINE_POWER := &"bloodline_power"
