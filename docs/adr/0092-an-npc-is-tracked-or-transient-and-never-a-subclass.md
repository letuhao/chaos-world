# 0092 An npc is tracked or transient and never a subclass

- Status: Accepted
- Date: 2026-10-03

## Context

The brief asks for several tiers of npc — major, story, minor, temporary — where the first two must be tracked and stage-change across the story while the last two spawn and disappear. It also restates the repo's governing premise: **an npc and the player have no difference.**

ADR 0074 already committed that premise to code: every inhabitant is an `Actor` built by one constructor, a role is a `StringName` tag, and no inhabitant gets a bespoke save path. It named the missing constructor explicitly. What it did not decide is the tier question, and the risk is now concrete — four tiers is an invitation to write `if tier == "major"` in four mechanisms, each of which then disagrees with the others.

ADR 0074 also separated a species (`WorldInhabitantDef` — a bear, owned by `world`) from an individual. The individual had no home.

## Decision

**Tier is data, and the only question it answers is whether this individual is remembered.**

- `NpcTier` is four `StringName` constants: `MAJOR` and `STORY` are tracked; `MINOR` and `TRANSIENT` are not. `NpcTier.TRACKED` is a validation set used once, in `normalize`, and **a mechanism never compares a tier** (ADR 0067).
- `NpcDef` is the authored **individual** — `npc_id`, `tier`, `realm_id`, `base`, and a `stages` ladder. `NpcDef.inhabitant_id` names the species but the module never names `WorldInhabitantDef`, so `npc` declares no dependency on `world` and `app/` stays the only place that resolves one into the other.
- **A stage is addressed by id, never by index.** `advance_stage(npc_id, stage_id)` is monotone and idempotent: re-advancing to the current stage succeeds and changes nothing, and a request naming an earlier stage returns `stage_regression` rather than rewinding a save. Reordering an authored ladder therefore cannot silently shift what an old save satisfies.
- **A stage grants authored magnitudes under the `npc_stage:` source, applied once.** `NpcStageProjection` strips then applies, always in that order, so an npc moving from stage 1 to stage 2 loses stage 1 rather than carrying both. Magnitudes are never derived from the realm power curve — a stage is an entity scale like a realm seed's `integrity_maximum`, and deriving it from the shared curve is the double-scaling trap ADR 0050 warns about.
- **The roster is a ledger in the player actor's `module_data`, not a second save file.** A bespoke roster file would be a bespoke save path, which ADR 0074 forbids and which `Actor.to_dict` already covers. `NpcRegistry` is an index over that ledger holding only the live actors for this room visit; it is rebuilt on `attach` and cleared on unload.
- **Off-stage presence is a ledger entry, not a live actor.** A tracked npc who is not in the room costs one `Actor.to_dict` payload of primitives. `resident()` reconstitutes on demand. A world with 300 authored inhabitants and 4 met costs 4 entries.
- **A transient npc has no roster entry at all**, which is what makes its despawn total: there is nothing to leave behind because nothing was written.
- The constructor is injected: `NpcApi.set_minter(Callable(ActorFactory, "spawn_npc"))`. The module never names `ActorFactory`, and a null injection returns null with an error rather than dereferencing nothing.
- `populate(def_ids, role, replace_first := true)` is bounded by `MAX_ROOM_POPULATION` and defaults to clearing first — a room load that forgets to clear leaves yesterday's cast standing in today's room, so the safe direction is the default.
- **`NpcBoot` (in `app/`) closes the inversion and is the only caller of `set_minter`/`attach`.** `install(player)` injects the constructor and binds the roster; `tick`, `populate_room` and `read_model` are the composition root's verbs. A module whose entry points nothing calls is a facade that can only return null, which is the failure ADR 0089 measured for statuses.
- **A read never installs.** `read_model` deliberately does not call `install`, because `attach` clears the live registry — a panel polling for state would empty the room it is rendering. Only `install` and `populate_room` may replace a cast.
- **`StatusLoop.tick` also ages bonds**, beside the statuses it already ticks. A relationship fading on a different clock from a status expiring is timing nobody can reason about, and `StatusLoop` is already the root's only time wire (ADR 0089). No second `_process` was invented.
- Authored cast ships as `.tres` under `game/data/npc/cast/`: a three-stage story elder ending in a terminal stage, a two-stage major smith, a transient drifter and a minor gatekeeper — so both tracked and untracked tiers are exercised by real content, not only by fixtures.

## Consequences

- Four tiers of npc cost a def and a stage ladder, not a code change. A new creature is data, exactly as ADR 0074 promised.
- A tracked story npc carries their stage, their actor payload and their last location across a save, with no new persistence code.
- The transient path cannot leak, because the untracked code path never receives the player actor and so never writes to `module_data`.
- `NpcApi` sits at exactly the twelve-method facade cap, so the first new verb forces a split rather than a thirteenth method.
- **Deliberately not decided here:** dialogue. The repo defers it (`DEF-0014`), and a tier system that wanted dialogue would have to reopen this ADR rather than smuggle a conversation tree through `NpcStageDef`.
- **Deliberately not decided here:** whether a tracked npc is tracked per quest-line. `tracked` is a single boolean today, and the first feature that needs "tracked but on cooldown" will have to widen it here.
- The cap values (`MAX_ROSTER` 256, `MAX_ROOM_POPULATION` 8, `MAX_PRESENCE_READ` 16, `MAX_TALLY_KEYS` 16) are named constants that refuse rather than trim, so an overflow fails loudly instead of writing a save that grows without limit.
