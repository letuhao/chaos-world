class_name FertilityStats
extends RefCounted

## Stat and status ids owned by the `fertility` module (ADR 0002).

const CONCEPTION_CHANCE := &"conception_chance"
const GESTATION_SPEED := &"gestation_speed"
const PARTURITION_SAFETY := &"parturition_safety"
const OFFSPRING_QUALITY := &"offspring_quality"
const MULTIPLE_BIRTH_CHANCE := &"multiple_birth_chance"
const MATERNAL_RESILIENCE := &"maternal_resilience"
const RECOVERY_RATE := &"recovery_rate"

const PREGNANCY := &"pregnancy"

## Gestation length for an actor whose body plan does not publish one. Reproduction parameters
## live on `RaceDef` (ADR 0062/0108), so this is the fallback for a raceless actor rather than
## a second source of truth — a content gap is not a reason to stall a pregnancy.
const DEFAULT_GESTATION_DAYS := 30.0
