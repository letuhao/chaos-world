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

## What Elder Wei's ladder means in play

The three-stage story elder is the ladder's worked example, so what it *does* in a run is part of this decision rather than a content detail.

**Each rung counts one verb, and a verb is a thing the world announces — never a thing a module increments.** `gatekeeper` counts `favours`, `sworn_servant` counts `oaths_sworn`, and each verb arrives only from an authored `npc_tally` beat in `data/event/events/`. `advance_verb` is therefore a *content contract with the roster*: a stage names a word, and some authored beat must exist that says it. A stage naming a verb nothing produces is a dead rung — reachable by no save, by no player, and by no test that drives production rather than calling `NpcApi.tally` itself. That is exactly how the elder sat one rung short: `oaths_sworn` existed only as a **destiny counter id** on a different ledger, and a counter id is not a tally verb. The two vocabularies share a spelling and nothing else.

**Retirement is a consequence of the second rung, not a separate one.** `retired` carries no `advance_after`, so the only way to reach it is to fill `sworn_servant`'s `advance_after = 5`. A ladder whose top rung needs its own verb has two producers to author and two chances to author one of them wrongly; making the terminal rung *derived* means "he retired" is a fact about how much he trusts you, which is the story the elder is written for, and it fails loudly at the second rung instead of quietly at the last.

**The consequence this accepts:** a stage is only as real as the beats that name its verb, and `tools arch` cannot see that. The check is a test that reads the shipped tree — `tests/modules/npc/test_elder_ladder_production.gd` drives `WorldPulse.pull` → `EventApi` → `EventBeatWriter` → `NpcApi.tally` and refuses to call `tally` itself, because a suite that called it directly would pass against a build in which no player action reaches the elder at all. A ladder is content agreeing with content, and the only honest auditor for that is a test that reads both halves off disk.

**Cost this ADR accepts:** one rung costs one authored event stage. Elder Wei's is now three stages rather than two, and the third is the cheapest possible beat — one fact, no prize — because the roster, not the event, decides what it means.

## Consequences

- Four tiers of npc cost a def and a stage ladder, not a code change. A new creature is data, exactly as ADR 0074 promised.
- A tracked story npc carries their stage, their actor payload and their last location across a save, with no new persistence code.
- The transient path cannot leak, because the untracked code path never receives the player actor and so never writes to `module_data`.
- **A row mints only where it was placed.** A spawned npc's `location_id` is the place the CALLER stood it up in, recorded at `spawn` time and never inferred later — so a presence read filtered by location and the spawn that fed it are one invariant, not two facts that can drift (BL-0715; this line carried BL-0790 in an earlier edit — see the correction appended below). The roster's `location_id` remains "where you last met them" and is published only for somebody with no live body; a filter with nothing to match answers nobody, which is how a settlement once reported four occupants as zero.
- `NpcApi` sits at exactly the twelve-method facade cap, so the first new verb forces a split rather than a thirteenth method.
- **Deliberately not decided here:** dialogue. The repo defers it (`DEF-0014`), and a tier system that wanted dialogue would have to reopen this ADR rather than smuggle a conversation tree through `NpcStageDef`.
- **Deliberately not decided here:** whether a tracked npc is tracked per quest-line. `tracked` is a single boolean today, and the first feature that needs "tracked but on cooldown" will have to widen it here.
- The cap values (`MAX_ROSTER` 256, `MAX_ROOM_POPULATION` 8, `MAX_PRESENCE_READ` 16, `MAX_TALLY_KEYS` 16) are named constants that refuse rather than trim, so an overflow fails loudly instead of writing a save that grows without limit.

### Clarification (N1, 2026-10-04) — appended, nothing above is edited

**Line 49's "where you last met them" is the DECISION, and it is now measured.**

The audit question was whether `despawn` leaving `entry.location_id` set is a leak of a
stale location: `npc_read_model.gd:70` publishes `live_location_id if is_live else
entry.location_id`, so an off-stage tracked npc's row reads back the room they were last
minted in, and `test_npc_tier.gd:121-126` asserted the presence half of that transition
without ever looking at the place — so nothing pinned the intent either way.

**It is correct, and the reason is that the remembered place cannot reach a room read.**
`presence_here()` iterates `NpcRegistry.present_ids()` — live bodies only — and `despawn`
releases the registry entry on the same call, so a departed npc is gone from the table the
filter walks. The remembered `location_id` is therefore reachable **only** through
`summary()` for somebody with no live body, which is precisely the case line 49 says it is
published for. The two facts answer two different questions and cannot be confused:
`NpcRegistry`'s place is *where the body is standing now*, the roster's is *where you last
met them* — the memory a content author needs for "where do I go to find this person next",
and explicitly never distance input (ADR 0072).

**Clearing it on despawn would be the actual regression.** It would discard the memory
ADR 0092's whole "remembered, not forgotten" contract for tracked npcs holds, and fix
nothing, because there is no leak to fix. Both halves are now pinned by
`tests/modules/npc/test_npc_despawn_place.gd`: two tests assert the last-met place IS
published and survives a save round trip, and two assert the other side — that a departed
npc does not haunt the room they left, and that the room filter is genuinely working while
they are in it, so the first pair cannot pass against a filter broken to match nobody.

### Correction (N6, 2026-10-04) — the location fix is BL-0715, not BL-0790

**Line 49's id was wrong. It now reads BL-0715, which is what the code has always said.**

The audit flagged a doc-vs-code disagreement: line 49 attributed the location fix to
`BL-0790`, while the code comments carrying the same claim named `BL-0715`
(`npc/api.gd:189`, `npc/api.gd:378`, `npc/api.gd:412`, `npc_read_model.gd:22`,
`npc_read_model.gd:82`, `npc_registry.gd:25`, `app/npc_boot.gd:121`, `app/npc_boot.gd:150`).
One of the two was stale. **The ADR was the stale one.**

Determined from `docs/backlog.jsonl` rather than by a vote:

- **`BL-0790` covers `F1` and `F4`** — "a spawned npc row must record the location it was
  minted for" (F1) plus two shipped cast members authoring a `faction` that is really a
  LOCATION (F4). Its guard is `test_npc_room_location.gd` and
  `test_npc_faction_resolution.gd`.
- The sibling entry opens "A **spawned row records the location it was minted for**
  (BL-0715, F1)" at `test_npc_room_location.gd:3`, and `test_npc_faction_resolution.gd:3`
  cites "BL-0715, F4". **So F1 was filed under two ids**, and the module's comments and test
  headers consistently used the older one.
- **`BL-0715` as it stands in `backlog.jsonl` is a DIFFERENT finding** — the
  fertility/seduction `can_meet` standing floor, "UNWIRED+VACUOUS", nothing to do with npcs.

So there are **two** stale references rather than one, and they point the same way:

1. **`docs/adr/0092` line 49** said `BL-0790` where every code comment says `BL-0715`.
   Corrected here to `BL-0715`.
2. **`docs/backlog.jsonl`'s `BL-0715`** is the fertility entry and does not describe the npc
   location fix at all. **`game/src/modules/npc/**` is owned by another agent and was NOT
   edited, and neither was that backlog row** — rewriting a finding another agent may be
   working from is exactly the collision this repo's safety rules exist to prevent. **That
   row is left for its owner**, and is recorded here as a known mismatch rather than
   silently absorbed: the correct home for "a spawned row records where it was minted" is an
   npc-module backlog entry, and the two npc guard suites already cite `BL-0715, F1` /
   `BL-0715, F4` in their headers.

**The ADR and the code now agree on `BL-0715`** — the id the module's own tests and comments
have used since the fix landed. Whether the backlog entry behind that id is correctly
*filed* is the separate, deliberately unfixed half above.

### Note (N6 follow-up, 2026-10-04) — which side was wrong, stated as a verdict

**The ADR was the wrong side, and the correction above is not in dispute.** Line 49 said
`BL-0790`; the code said `BL-0715`; line 49 now says `BL-0715`. That much is settled by
reading two artifacts.

The second half of the correction above — that `backlog.jsonl`'s `BL-0715` is a fertility
entry rather than an npc one — was left open because rewriting a finding another agent may
be working from is the collision this repo's rules exist to prevent. **It is still open and
still deliberately so:** `BL-0715` in `docs/backlog.jsonl` remains the
fertility/seduction `can_meet` finding, and it is **not** the npc location fix. The npc
fix is properly `BL-0790` (F1 + F4), which is why both ids appear in this story and why
neither can simply be deleted.

**The honest statement of where the disagreement now lives:** the code comments and the
npc guard test headers cite an id (`BL-0715`) that the backlog defines as something else.
That is a citation defect in code this slice does not own (`game/src/modules/npc/**` and
`tests/modules/social/**` are other agents' live paths), so it was not touched here. The
first agent who owns those files should repoint them at `BL-0790`. Until then, treat
`BL-0715` in those comments as **meaning BL-0790**, and treat the backlog row itself as the
thing that is wrong — it should have carried a distinct id, which is why the fix is filed
under two.
