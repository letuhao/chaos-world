class_name ModsApi
extends RefCounted

## Public facade for the `mods` module (ADR 0184).
## Other modules may reference ONLY this file (`api.gd`).
##
## The module is the locked loader: it is policy plus a parsed-manifest plus a
## sorted order, never a plugin host. Boot comes in two pieces across waves:
## this facade computes the load order and stamps RegistrationContexts (W2),
## and a later wave replaces the recorded rows with real wiring (W3+). A mod
## can never replace the loader itself, so boot policy stays uniform no matter
## what content a mod registers.

## The manifest contract version the loader speaks. Surfaced so a mod tooling
## probe can read it without parsing the loader's source.
const LOADER_API_VERSION := ModLoader.API_VERSION


## Parse one `mod.json` text into the normalized manifest row or a NAMED
## parse error. `source_path` is only used for error detail.
static func parse_manifest(text: String, source_path: String = "") -> Dictionary:
	return ModManifest.parse(text, source_path)


## Find and parse every `mod.json` under `roots`. First bad manifest or
## duplicate id wins, named.
static func discover_mods(roots: Array) -> Dictionary:
	return ModLoader.discover(roots)


## Discover, validate and sort: the deterministic load order, or a NAMED
## cause (cycle, missing dependency, version mismatch, api mismatch,
## engine version mismatch, duplicate id, bad manifest). On success also
## returns the per-mod RegistrationContext rows recorded through the five seams.
static func load_order(roots: Array) -> Dictionary:
	return ModLoader.load_order(roots)


## A fresh registration context, for a caller that wants the five seams
## without a loader pass (tests, in-repo registrants in a later wave).
static func build_context(mod_id: String = "") -> RegistrationContext:
	return RegistrationContext.new(mod_id)
