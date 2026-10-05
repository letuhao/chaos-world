class_name DoctrineTemplateModApi
extends RefCounted

## THE TEMPLATE MOD FACADE. It is not a System and it is not a design: ADR 0273
## has the framework ship the seams and no System, and this mod exists to prove a
## System can SHIP as one — that a template authored outside `game/src` is
## discovered, declares its own vocabulary, admits its Systems, and is then driven
## entirely through [DoctrineApi].
##
## Three files, three jobs, and nothing else:
##
##   - `mod.json`      the manifest: id, version, priority, one module.
##   - `stats.json`    the stat rows and the pools they read (ADR 0275). Read by
##                     `ModRuntime.finalize` through the sixth seam — see
##                     [method boot] for why this facade does not read it.
##   - `doctrines.json` the Systems themselves — ids, boards, tiers, claims. This
##                     facade's ONE file, and JSON rather than GDScript because
##                     `tools/data.py` cannot execute GDScript, so numbers
##                     authored in code are numbers no Python gate can read
##                     (ADR 0273, ADR 0275).
##
## ## What this facade deliberately does NOT do
##
## It never ticks, never reads a clock and never reaches the scene tree
## (DEF-0111). It never grants a stat: a row's effect is a `StatusEffect` through
## `Actor.add_status`, and `stats.json` only CLOSES the pool vocabulary, which is
## what makes a typo'd pool id a refusal instead of a silent `0.0`.

## Where this mod's JSON lives. A mod's own directory, beside its `mod.json`.
##
## The mod id and the module name are spelled in `mod.json` and the System ids in
## `doctrines.json`, and NEITHER is restated here: a GDScript list of ids the JSON
## already declares is a second literal of one fact with nothing keeping the two in
## agreement (ADR 0066), and the whole point of the block being JSON is that
## `tools/data.py` reads the only copy.
const MOD_DIR := "res://tests/fixtures/mods/doctrine_system"
const SYSTEMS_FILE := MOD_DIR + "/doctrines.json"

## How many actors this mod has been attached to, and the last one.
##
## The ONLY state the facade owns, and it exists so the loader seam is
## OBSERVABLE: `AttachPipeline.attach_module` loads this script and calls
## `attach(actor)`, and a counter is the difference between "the mod loaded" and
## "the mod RAN".
static var attach_count: int = 0
static var last_actor_id: StringName = &""


## The mod's entry point, handed the [RegistrationContext] the loader stamped for
## this mod. It reads ONE file — `doctrines.json` — and admits each System with the
## pools [method RegistrationContext.declared_resource_ids] already holds, so a
## System cannot name a pool this mod did not introduce: an undeclared one fails at
## [method DoctrineApi.attach] as `UNDECLARED_POOL` rather than earning a silent
## `0.0` forever.
##
## ## Why it does NOT read `stats.json`
##
## `ModRuntime.finalize` reads the block through
## [method RegistrationContext.declaration_path] and plays it through
## `declare_stats`, so by the time a mod's entry point runs the pools are on the
## context. A mod that read the file again would be a SECOND reader of one
## declaration whose two answers nothing keeps in agreement (ADR 0066), and its
## `ok` would be about the mod's own parse rather than the framework's.
##
## Returns `{ok, attached, refused, pools}` and books nothing it could not admit, so
## a caller can report the refusal and know nothing half-registered.
static func boot(ctx: RegistrationContext) -> Dictionary:
	var pools := ctx.declared_resource_ids()
	var attached: Array[String] = []
	var refused: Array[Dictionary] = []
	var entries: Array = _read_block(SYSTEMS_FILE).get("systems", []) as Array
	# `entries` is the authored array and this walk appends to two OTHER lists, so
	# it cannot outrun its input (INC-0002).
	for entry in entries:
		var rule := build_rule(entry as Dictionary, pools)
		var verdict := DoctrineApi.attach(rule)
		if bool(verdict.get("ok", false)):
			attached.append(str(rule.system_id()))
		else:
			(
				refused
				. append(
					{
						"system_id": str(verdict.get("system_id", "")),
						"reason": str(verdict.get("reason", "")),
						"detail": str(verdict.get("detail", "")),
					}
				)
			)
	# A mod whose declaration never reached the context admits Systems with NO
	# pools, so every priced row is refused as `UNDECLARED_POOL`. That is the
	# loud direction and it is why the refusal is reported rather than patched over.
	return {
		"ok": refused.is_empty() and not pools.is_empty(),
		"attached": attached,
		"refused": refused,
		"pools": pools,
	}


## The mod-module attach verb `AttachPipeline.attach_module` calls with the actor.
##
## It touches nothing on the actor, on purpose. ADR 0272: a System's ledger is
## created by `DoctrineApi.join` and normalized on every read, so an actor who
## never joined reads a default and an actor who loaded a save reads their own —
## there is no per-actor binding left for a System to make. Opting in is the
## player's press on `join`, and a verb that restored a snapshot nobody had would
## be a verb with no case.
static func attach(actor: Actor) -> void:
	attach_count += 1
	last_actor_id = actor.id if actor != null else &""


## What a panel needs about this mod's Systems, and nothing it would have to
## re-derive: the facade's whole read model, primitives-only by contract.
## `{}` with no actor, which is an ordinary state rather than an error.
static func panel_state(actor: Actor) -> Dictionary:
	return DoctrineApi.summary(actor)


## One System from its JSON row and the pools the declaration accepted. A fresh
## instance every call: the registry refuses a second `attach` of one id, and a
## shared instance would let one System's board be edited under another's reader.
static func build_rule(entry: Dictionary, pools: Array[StringName]) -> DoctrineTemplateRule:
	var rule := DoctrineTemplateRule.new()
	rule.id = StringName(entry.get("id", ""))
	rule.label = str(entry.get("display_name", ""))
	rule.pools = pools
	rule.points_max = int(entry.get("points_max", 0))
	rule.tier_points = int(entry.get("tier_points", 1))
	rule.tier_names = _strings(entry.get("tier_names", []))
	rule.points_per_redeem = int(entry.get("points_per_redeem", 0))
	var claim: Dictionary = entry.get("earn", {}) as Dictionary
	rule.earn_kind = StringName(claim.get("kind", ""))
	rule.earn_amount = float(claim.get("amount", 0.0))
	rule.rows = _rows(entry.get("rows", []))
	return rule


## One board row. Every JSON key is carried through as a `StringName` key and the
## DECLARED values are coerced, because JSON delivers `String` keys and every
## number as a float and the registry's `missing_keys` and `is_primitive_payload`
## cannot read that shape. An extra key is legal — the contract permits
## primitives-only detail keys per row — while a MISSING declared key is refused by
## `DoctrineRegistry.attach`, which is the gate that owns it.
static func _row(source: Dictionary) -> Dictionary:
	var out := {}
	for key in source:
		out[StringName(key)] = source[key]
	out[&"row_id"] = StringName(out.get(&"row_id", &""))
	out[&"label"] = str(out.get(&"label", ""))
	out[&"tier_min"] = int(out.get(&"tier_min", 0))
	out[&"pool"] = StringName(out.get(&"pool", &""))
	out[&"amount"] = float(out.get(&"amount", 0.0))
	out[&"repeatable"] = bool(out.get(&"repeatable", false))
	out[&"max_count"] = int(out.get(&"max_count", 0))
	return out


static func _rows(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not raw is Array:
		return out
	# `raw` is the authored array; `out` is a different container and does not
	# feed it, so the walk cannot outrun its input (INC-0002).
	for entry in raw as Array:
		if entry is Dictionary:
			out.append(_row(entry as Dictionary))
	return out


static func _strings(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if not raw is Array:
		return out
	for entry in raw as Array:
		out.append(str(entry))
	return out


## A JSON file beside this mod's `mod.json`, or `{}`. An absent block declares
## nothing and that is legal (ADR 0083: does-not-exist is not exists-and-refused),
## so a missing file is not an error here — the seam decides, not this reader.
static func _read_block(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}
