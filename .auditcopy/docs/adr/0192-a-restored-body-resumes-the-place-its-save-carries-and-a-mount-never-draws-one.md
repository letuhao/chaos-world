# 0192 A restored body resumes the place its save carries, and a mount never draws one

- Status: Proposed
- Date: 2026-10-04
- Depends on: ADR 0027 (a module ledger rides `module_data`), ADR 0113 (the owner of the moment writes, nobody polls), ADR 0117 (one beat path, one writer)

## Context

A RESTORED save could never earn an event-sourced fate. Three measured facts, one chain:

- `WorldStage.new()` had exactly ONE hit in `game/src`: `character_creation_program.gd:218`, reached only through creation `commit`.
- `restore_actor` (`app/item_workbench_app.gd`) rebuilt the Actor from the envelope, mounted the per-actor module list, and returned — with no stage and therefore no place.
- `EventApi.set_location`'s publisher IS installed by the root, but it fires only on the creation path, because only `WorldStage.mount` / `enter` fire it.

So the event ledger's `location_id` stayed `EventApi.NOWHERE` (`""`), and `EventApi.available` (`event/api.gd:83`, filter at `:93`) dropped every authored event BEFORE its trigger was read. `EventPrize.apply` — a live, correct earn site — was unreachable for every returning player. Three vacuous ladders behind one missing mount.

## Decision

**A restored body is resumed into the place its save CARRIES. A mount never DRAWS one.**

- **Resolve by READING `WorldSpawnApi.current(body)`.** The durable `world_spawn_state` ledger already round-trips: `core/actor.gd:301-307` writes every `module_data` key except two named ones, `:397-398` restores all of them, and `save/api.gd:61` puts `actor.to_dict()` into the envelope. VERIFIED, so the save/load concern is NOT the defect.
- **`WorldSpawnApi.random` is never called on the restore path.** A draw is a silent WORLD REWRITE, not a placement: it increments `visits` and rewrites `source`, `seed` and `display_name` on that durable ledger (`world_spawn_state.gd:145-158`). Restoring would therefore TELEPORT a returning player and persist the teleport as where they left off. Creation keeps its draw — placing a NEW hero somewhere on purpose is the one moment that is authored, not resumed.
- **Mount through the SAME seam creation uses**, and **one stage per root** held in nil-guarded fields. `WorldStage._current` and `_mounted_player` are STATIC, so a per-restore `WorldStage.new()` leaves the newest in `_current` and the previous adapter orphaned — the half-swapped world `CharacterCreationProgram._stand_in_the_world` refuses to create. A boot takes exactly one of the two branches, so creation's stage and this one never coexist.
- **The seam is the ONLY path to the event ledger** (ADR 0117). `app/` installs the `Callable`; the STAGE fires it. `app/` never writes `event`'s ledger directly and `event/` is never edited.
- **Order is load-bearing.** The mount runs at the END of `restore_actor`, after `_mount_player_modules`: `EventApi.attach` runs `EventState.normalize` over the ledger, so a publish before it would write a half-normalised row.
- **Refusals are NAMED, never rounded up to a draw.** A save naming no place is `not_located`; a place no `.tres` backs is `unknown_location` from the mount. Both ride the restore's own answer as ADDITIVE keys (`located`, `location_id`, `world_told`) — a save that names nowhere stays a correct playable state rather than being teleported somewhere to look busy.

## Consequences

- **`available()` is non-empty for a restored hero** at any place an authored event names, after the world's OWN clock advances the `WorldAmbient` facts a test must not write itself.
- **An empty event list is not a refused restore.** Standing somewhere with nothing to do is playable; the fix must not turn "nothing here" into "refused boot".
- **A corrupt place cannot brick a boot** — the restore still returns `ok: true` and reports `located: false` with a reason.
- **A stage left mounted leaks across suites.** `WorldStage` holds process-wide statics, so any suite that mounts must `leave()` in its first teardown statement.
- **`app/` is at its line ceiling.** These lines are charged against it, exactly as the interaction seam and travel were.
- **No boundary moved.** `app` already depends on `event` and `world_spawn`; no registry edge changed and `event/`, `world_spawn/`, `core/` and `contracts/` are untouched.

## Rejected

- **B — the seam alone.** `WorldStage.set_location_publisher` installs a Callable; without a `WorldStage` nothing fires it, which is the defect. And calling `EventApi.set_location` from `app/` makes the root a second writer of a ledger `event` owns.
- **C — fix the save/load round trip.** Both ledgers ALREADY round-trip. A concern that is not the defect would have been re-fixed until something changed, which is how a real defect stays buried under a plausible one.
- **D — leave it and record it.** Status quo is a recorded consequence of a decision; here the decision was never taken, which is what left a shipped game where a returning player earns nothing.
