class_name BuildingStats
extends RefCounted

## The `clan_building` module's own stat-id vocabulary (ADR 0895).
##
## Every id here is a bounded, non-combat SUMMARY. Buildings grant recognition
## and infrastructure, never combat power (ADR 0064).

## Total number of buildings constructed.
const BUILDING_COUNT := &"building_count"
## Total building levels across all buildings.
const BUILDING_LEVEL := &"building_level"
## Current clan level (1-5).
const CLAN_LEVEL := &"clan_level"
## Total upkeep due per day.
const UPKEEP_DUE := &"building_upkeep_due"
## Number of techs researched.
const TECH_COUNT := &"building_tech_count"
