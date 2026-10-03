class_name DomainBoot
extends RefCounted

## The composition root's domain wiring (ADR 0072-0075). Wiring, not rules: `app/`
## injects the constructor; the `domain` module owns what a map, a room and an inhabitant
## mean.
##
## ## Why this file exists
##
## The audit measured it: **13 of 13 domain source files had zero production call sites.**
## `DomainSpawner.spawn` needed a constructor to mint an `Actor` and nothing installed one,
## so it could only ever return null — a feature nobody can start is decoration, which is
## the same failure ADR 0089 measured for statuses and ADR 0074 for npcs.
##
## This is the domain twin of `NpcBoot`, and it exists for exactly the same reason. It is
## deliberately wiring-only: no rules, no state of its own, nothing that ticks.
##
## ## One clock, no clock of its own
##
## Nothing here ticks. Severe environments resolve through `EnvironmentField`, which is
## driven from the same `StatusLoop` tick every other status uses (ADR 0089); a second
## `_process` would be the stateful-`app/` shape `tools/arch/rules.py` rejects.


## Install the inhabitant constructor. Idempotent, so calling it on boot and again after a
## load is the intended usage rather than a mistake.
static func install() -> void:
	# The one place that knows the concrete constructor. Handing the module the static
	# function itself, rather than a lambda that forwards to it, is what keeps `domain/`
	# free of any reference to `ActorFactory` (ADR 0002) — and it is also the only form the
	# engine boots: a typed lambda whose body calls another script's static function killed
	# the process with an access violation on the shell's first frame, with nothing logged.
	# `spawn_inhabitant` takes the minter's two arguments positionally.
	DomainSpawner.set_minter(ActorFactory.spawn_inhabitant)


## The whole domain read model for one screen or the headless driver (BL-0220): which
## domains are authored, what is in the active one, and who is standing there.
##
## Deliberately does NOT call `install` on a read path beyond the constructor injection,
## because installing is idempotent and a read must never mint anything.
static func read_model(player: Actor) -> Dictionary:
	return {
		"has_actor": player != null,
		"templates": DomainApi.templates(),
		"active": DomainApi.summary(player),
	}


## Generate and enter an authored domain in one call, then report what the player is
## standing in. This is the production entry point that closes the chain the audit found
## severed: a template is loaded, a map is generated, the contract is enforced, and the
## run becomes the actor's active domain.
##
## A template that cannot produce a contract-valid map is refused BY NAME. A run that
## begins in a broken map is a run the player cannot finish, and the generator has already
## reported exactly why.
static func enter_domain(player: Actor, template_id: StringName, seed_value: int = 0) -> Dictionary:
	install()
	var entered := DomainApi.generate_and_enter(player, template_id, seed_value)
	if not entered.get("ok", false):
		return entered
	return {
		"ok": true,
		"domain_id": entered.get("domain_id", ""),
		"room_count": entered.get("room_count", 0),
		"map": DomainApi.map_summary(player),
		"population": DomainApi.population(player),
		"zones": DomainApi.environment_zones(player),
	}


## Leave the domain. The run is discarded; the discovered set is KEPT, because the map
## remembers where you have been even though the inhabitants do not (BL-0252).
static func leave_domain(player: Actor) -> Dictionary:
	return DomainApi.leave(player)
