class_name SectLedger
extends RefCounted

## The `sect` module's ledger plumbing: read the actor's versioned ledger, append the
## explanation trail, write a claim back, and persist + project + announce.
##
## Extracted from `SectApi`, which had grown past the file budget. `SectApi` calls in and
## this file never names `SectApi`, so the pair cannot load in a cycle — the four verbs
## that stay on the facade because they pivot on something private to it (`_claim` calls
## `attach`, `_regard` owns the one `social` edge, `_declare_world_schism` reads the
## facade's world-store seam) are the only ones that could not travel.
##
## Every verb here is called by the facade's write arms, so a refusal upstream writes
## nothing at all (ADR 0084): these helpers only ever run on a path that already passed
## its own refusals.


## The actor's ledger, normalized against the catalog, so a caller always operates on a
## well-formed ledger. The `module_data` key is read from `SectState` — the module's own
## owner of it — rather than from `SectApi`, which would make this file name its caller.
static func normalized(actor: Actor) -> Dictionary:
	return SectState.normalize(
		actor.get_module_data(SectState.MODULE_KEY), SectCatalog.instance().known_position_ids()
	)


## Append one line to the bounded explanation of how the member got here.
##
## A trail, never an audit log: `SectState.HISTORY_LIMIT` caps it so a save cannot
## grow without limit, and a refused verb never reaches this — it writes nothing at
## all (ADR 0084). `detail` is a string rather than a number so `force` and an
## ordinary promotion stay distinguishable to whoever reads the trail later.
static func record(ledger: Dictionary, kind: String, id: StringName, detail: String) -> void:
	var history: Array = ledger["history"]
	if history.size() >= SectState.HISTORY_LIMIT:
		return
	history.append({"kind": kind, "id": String(id), "detail": detail})


static func write_claim(ledger: Dictionary, claim: InstitutionClaim) -> void:
	var payload := claim.to_dict()
	ledger["position"] = String(payload["position"])
	ledger["standing"] = int(payload["standing"])
	ledger["standing_cap"] = int(payload["standing_cap"])
	ledger["obligation"] = payload["obligation"]


## Persist, rebuild the projection, then announce. The three effects are one
## operation because a half-applied change — stats without a ledger, a ledger
## without stats — is the one state a player cannot recover from.
##
## The RETURN VALUE is persisted, never the argument: `SectProjection.apply` rewrites
## `applied_standing` / `granted_percent` as part of the rebuild, so the ledger handed
## in is stale the moment the projection runs.
static func persist(
	actor: Actor, ledger: Dictionary, kind: String, standing_delta: int = 0
) -> void:
	var written := SectProjection.apply(actor, ledger)
	var sect_id := SectState.institution(written)
	var bus := SectProjection.events()
	bus.claim_changed.emit(String(actor.id), sect_id, SectState.position(written), kind)
	match kind:
		"join":
			bus.membership_changed.emit(String(actor.id), sect_id, true, "")
		"leave", "expelled":
			# An expulsion ends a membership the same way a resignation does, and a
			# consumer reading only this signal must not be able to tell that the two
			# are different — the ledger is where that distinction lives (ADR 0084:
			# "may this member expel another" is an authored question, and the cause
			# that was applied is the answer to it).
			bus.membership_changed.emit(String(actor.id), sect_id, false, "")
		_:
			if standing_delta != 0:
				bus.standing_changed.emit(
					String(actor.id), sect_id, standing_delta, SectState.standing(written)
				)
