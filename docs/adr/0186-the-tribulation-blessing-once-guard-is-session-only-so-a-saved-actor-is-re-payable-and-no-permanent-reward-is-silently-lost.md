# 0186 The tribulation-blessing once-guard is session-only, so a saved actor is re-payable and no permanent reward is silently lost

- Status: Accepted
- Date: 2026-10-04
- Supersedes: ADR 0089's premise that a once-guard may ride `actor.module_data` — the guard is
  session-only, like the statuses ADR 0089 kept out of the save
- Resolves: DEF-0235, DEF-0150

## Context

`TribulationBlessing.award` (`modules/status/tribulation_blessing.gd`) pays one of three
PERMANENT cultivation statuses — `earth_bulwark`, `light_halo`, `wood_bloom`, every one
`duration = -1.0` — and then wrote its once-guard `REWARDED_KEY` into `actor.module_data`.
`module_data` IS serialized (`core/actor.gd:344`) and restored (`core/actor.gd:397-398`).
`Actor.to_dict()` emits no `statuses` key (ADR 0089), so the blessing itself does not survive.

The chain, confirmed line by line: survive a tribulation -> the blessing is applied and
`REWARDED_KEY` is saved -> save & reload -> `core/tribulation.gd:156,193` refuses a re-fight on
the restored `SURVIVED` outcome and `award` answers `ALREADY_REWARDED`
(`tribulation_blessing.gd:118-119`) -> **the permanent reward is gone and can never be
re-earned, silently.** That is a data-loss bug, and the class this game refuses: ADR 0140
recorded the identical shape for wounds ("the save file was the one mechanism that undid ADR
0070's central irreversible fact ... for free, on every load, and it did so silently").

ADR 0089 wrote the trigger for this decision — persistence becomes its own ADR with
`SCHEMA_VERSION 4 -> 5` "once the catalogue ships (ADR 0090) and a cultivation outcome can read a
status across a save". Both clauses fired: the catalogue ships 20 defs, and a tribulation pays a
permanent. Nobody made the ruling, so the guard quietly took a persisted slot it was never
authorised to take. ADR 0061 says the reward is paid ONCE — once for that fight, not once ever
recorded in a ledger the reward itself is absent from.

## Decision

**`REWARDED_KEY` does not ride `module_data`. The once-guard is session-only; the permanent
reward is re-payable after a load. No schema bump: `SCHEMA_VERSION` stays 5.**

- The guard moves off `module_data` into the module's own session-only store, the same shape
  `StatusRuntime` keeps its live records in. `Actor.to_dict()` reaches neither, so no save
  carries it.
- **Once-only within a session is unchanged, and is what this ADR protects.** `award` still
  refuses a second pay on the same decided record, and it does so on the record's OWN `outcome`
  guard (`core/tribulation.gd:156,193`) plus this in-session marker. A caller that observes the
  same decided fight twice in one session still cannot double-pay — the ADR 0061 defect under a
  new name does not return.
- **After a load, a survived tribulation is re-payable.** The restored actor carries the
  `SURVIVED` outcome (deliberately persisted, `core/tribulation.gd:99-101`) and nothing else, so
  the next observation of that record pays the blessing again. A permanent reward a player
  earned is never deleted by an autosave.
- **Rejected — persist cultivation status ids** (a `statuses` payload slot, `SCHEMA_VERSION
  5 -> 6`, real rehydration). It is the eventual end-state, but it is not what this defect needs
  and ADR 0089's reasons are unreversed: a designer retune would rewrite old saves, and the slot
  would carry potency, escalation state and authored def ids into every save. Paying a schema
  bump across every save — the cost ADR 0089 flagged as needing its own decision — before the
  catalogue has settled is a premature migration, and taking it merely because it is the most
  complete answer imposes that cost the owner did not ask for. It stays available as its own ADR
  once the catalogue is stable.
- **Rejected — stop paying permanent statuses from tribulation** (option c). It deletes authored
  content and a producer (`TribulationBlessing`) that a suite and a screen
  (`ui/panels/tribulation_panel.gd`) depend on, to avoid a fix that is one session marker wide.
  That is the largest price for the smallest defect.

## Consequences

- The data loss is closed: a survived tribulation's permanent blessing survives an autosave and is
  re-offered on the next observation after a load. The player loses nothing, and nothing is paid
  twice in a session.
- `module_data` is no longer a place a session-only fact may hide. That is the general lesson for
  a future reader: `module_data` IS persisted, so a once-guard placed there must guard something
  that also survives the save, or it is a guard for a reward the save deleted.
- A re-pay after a load re-applies through `StatusApi.apply_cultivation`, so the blessing is
  rebuilt from the authored def — which is what makes it re-earnable at all while the catalogue
  is the only source of a def (ADR 0089's reason for not persisting a def id).
- No save written before or after this change carries the guard, so nothing migrates and no
  player loses an already-earned reward to the change itself.
- `tests/core/test_status_round_trip.gd`, which asserted that statuses PERSIST across a save, is
  inconsistent with this ADR; it is corrected to assert the contract this ADR sets — a saved actor
  is re-payable and the blessing is not silently lost — rather than deleted.