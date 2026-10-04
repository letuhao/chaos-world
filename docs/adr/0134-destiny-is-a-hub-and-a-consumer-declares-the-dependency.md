# 0134 Destiny is a hub, and a consumer declares the dependency

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0065 (adds the hub contract; its earn-only invariant is unchanged)
- Depends on: ADR 0114 (a beat names its occurrence), ADR 0132 (the director offers)

## Context

ADR 0065 records the invariant — fate is earned, never chosen, never removed. It does not
record the contract a *consumer* depends on, and the standard for this module is now
**enough surface for another feature to use destiny**, not internal correctness. Two consumers
already exist (`quest`, `event`) and one more is wanted (equipment/uniques). None of them had
the rules written down, and the one failure that has already happened — an undeclared
dependency — is invisible to the gate that is supposed to prevent it.

## Decision

### 1. The consumer surface is exactly twelve verbs

`DestinyApi` (`game/src/modules/destiny/api.gd`) is the whole of it, at the twelve-method cap
(`rules.MAX_FACADE_PUBLIC_METHODS = 12`). No thirteenth verb: a new read folds into `summary()`
rather than growing the facade. Grouped by what a call is allowed to do:

| Verb | Signature | Kind | Guarantees |
|---|---|---|---|
| `earn_fate` | `(actor, fate_id, source := "") -> Dictionary` | mutate | Exactly-once. Unknown id → unchanged ledger. Returns the ledger. |
| `earn_destiny` | `(actor, destiny_id, source := "") -> Dictionary` | mutate | Exactly-once; exclusive within `group`; carries `grants_fates`. Prereq or group unmet → unchanged ledger. |
| `record` | `(actor, counter_id, amount := 1) -> int` | mutate | Rising only; a negative or zero amount moves nothing. Returns the value *after* the delta. |
| `has_fate` | `(actor, fate_id) -> bool` | read | `false` for a null actor. Never a content lookup — the ledger only. |
| `has_destiny` | `(actor, destiny_id) -> bool` | read | Answers true for an authored `gate_aliases` id, **in both directions — on the READ path only**. `earn_destiny` does NOT resolve an alias: it looks the id up as a definition and refuses silently if there is none, because a pure narrative alias ships no `.tres`. Earn the DECLARING id, never the alias. A contested alias (two destinies claiming one) resolves to nothing rather than to whichever the scan reached first, and nothing audits for that collision. |
| `events` | `() -> DestinyEvents` | read | The signal bus. **Replaces `counter`, which was retired at the cap** — read a counter through `state(actor)["counters"][counter_id]`. This table was corrected 2026-10-03; it previously listed `counter`, which no longer exists and which a consumer calling would fail to parse. |
| `destinies` | `(actor) -> Array[StringName]` | read | Held ids, ordered by STRING value (not by earn order — read `state()["destinies"][id]["sequence"]` for that). |
| `fates` | `(actor) -> Array[StringName]` | read | Same shape: held only, ordered by string. |
| `state` | `(actor) -> Dictionary` | read | The versioned ledger **exactly as core persists it** — the save payload. Never reach into `actor.module_data` instead. |
| `summary` | `(actor) -> Dictionary` | read | Primitives only; one call answers a codex screen. **Catalog-driven, not player-driven**: `summary()["fates"]` and `["destinies"]` carry held AND unheld rows, so filter on each row's `held`, and note `fate_count` is the HELD count and will not equal `["fates"].size()`. `available` / `blocked_by` exist only on UNHELD destinies — use `.get()`. A `teaser`-visibility fate is absent entirely, so absence means "not disclosed", not "not earned". |
| `gate` | `(actor, requirement) -> Dictionary` | evaluate | `{}` → ungated/open. Otherwise one of six authored verbs. Always `{ok, reason, unmet}`; `ok` is the whole answer. Refuses closed and names itself on an unknown verb or a malformed requirement. Emits `gate_failed` on **every** refusal, including every poll — treat it as telemetry, never a player-facing notice. `reason` is an open set: `""`, `"unmet"`, `"malformed"`, `"unknown_verb"` (plus `"delegated"` if you route through `EventGate`). On a refusal `unmet[0].id` is empty. |
| `attach` | `(actor) -> void` | lifecycle | Normalizes the ledger, rebuilds the stat projection and the `Actor.traits` mirror. Idempotent. Grants nothing. |

**Write verbs belong to the owner of the moment, never to `destiny`.** `destiny` never calls
back into the system that earned a fate: it is a write target, not a listener (ADR 0065). A
consumer that wants to *react* to an earn observes `DestinyApi.events()` (ADR 0136/ADR 0149);
a consumer that wants to *cause* one calls `earn_*` at the place it already decided the thing
happened.

### 1a. An earn returns the LEDGER, never a verdict — so verify it

**The single most expensive thing a consumer can get wrong here.** Every refusal path in
`earn_fate` / `earn_destiny` returns the ledger *unchanged*: a null actor, an already-held
entry, an unknown id, an unmet prerequisite and a closed exclusivity group are byte-identical
in shape, and none carries an `ok`. A refused earn also **queues nothing** — there is no pending
flag and no retry — so a consumer that treats the call as "already offered" never gets the
entry.

The only correct idiom, taken from `character_creation_flow.gd:260-262`:

```gdscript
DestinyApi.earn_destiny(actor, choice_id, SOURCE)
if not DestinyApi.has_destiny(actor, choice_id):
    return _grant_refusal("gate_unmet", _unmet_for(actor, choice_id))
```

Do **not** copy `EventPrize._apply_row` (`event_prize.gd:95-96`), which returns `ok: true`
immediately after the call with no verification — a typo'd or unknown fate id is a silent
no-op reward.

Two related shapes: `record` with a non-positive amount writes nothing and returns the
unchanged total, which is indistinguishable from a real read; and `earn_destiny` both
`requires_fates` and `grants_fates` may name the same id, so a destiny can refuse on a fate it
would otherwise have carried (real case: `the_chosen_instrument` requires
`reborn_in_a_lesser_vessel` without granting it).

### 1b. Two authoring hazards that cost another branch permanently

- **The facade is at its cap.** Twelve public methods against
  `MAX_FACADE_PUBLIC_METHODS = 12` (`tools/arch/rules.py`). A thirteenth fails `tools arch` —
  loudly, but the message tells *you* to split *your* interface when the remedy is to fold the
  read into `summary()` here. Do not edit `tools/arch/**` to raise the cap.
- **Do not author a destiny into `group = &"origin"`.** That group holds three shipped
  destinies and is not inert: `character_creation_flow.gd` filters on it to build the
  character-creation picker, so a fourth member appears in that picker whether you intended it
  or not — and is then silently ungrantable there, because `_is_origin` also requires a
  `RACE_BY_ORIGIN` entry. `data audit` only *warns* on a multi-member group. Use a new group name.

Also: `data audit` does not validate `gate_aliases` at all, so an alias naming no destiny, or
one two destinies both claim, passes the build and then resolves to nothing.

### 2. A consumer MUST declare `destiny` in `tools/arch/registry.json`

**This is the rule that already failed once.** `BARE_REF_UNITS` in `tools/arch/rules.py`
(frozenset `{"ui", "app", "contracts"}`) excludes `modules/*`, so a bare module-to-module
reference is invisible to `tools arch` *and* to `_find_cycle`, which is fed by the registry
alone. `rules.py` states the limitation outright: such a reference "is reported as an unresolved
count rather than enforced". Measured with `tools arch` on this tree: `ok boundaries ok (15896
files, 37 modules)` with the undeclared edge in place.

The live cautionary case: `quest` calls `DestinyApi` from five places —
`quest_grants.gd` (`earn_fate`, `earn_destiny`), `api.gd` (`gate` at three sites) — while
`registry.json` still lists `quest` with deps `[contracts, core]` only. `event` does the same
thing correctly and declares `destiny` in its deps. So the registry already knows how to record
this edge; the quest side is simply unrecorded (DEF-0167).

Consequences an agent must carry: an undeclared edge is how a module **cycle** ships unnoticed;
a `destiny` dep is a one-line registry edit, never a weakening of a rule; and a consumer that
edits `tools/arch/**` at all is outside its ownership — the registry entry is the deliverable.

### 3. The earn-source matrix (measured 2026-10-03)

| Source | Call site | Owns the call? | Declares `destiny`? | Live in play? |
|---|---|---|---|---|
| Quest completion | `quest_grants.gd:62,67` via `QuestApi._complete` | `quest` | **no** (DEF-0167) | no — `QuestApi.accept` has no production caller; no quest is ever accepted (DEF-0183) |
| World event prize | `event_prize.gd:95,100` via `EventPrize.apply` | `event` | yes | no — `EventApi.set_location` has no production caller, so the ledger stays at `NOWHERE` and `available()` filters all 7 authored events (DEF-0183) |
| Character creation (origin) | `character_creation_flow.gd:198,201` | `app/` | n/a (app may depend on anything) | no — the screen is shipped but unrouted (DEF-0186) |
| Combat (kills, duels) | — | `combat` | no | **not built.** Decision points exist: `exchange.gd:428 _record_defeat`, `duel.gd:42 record_defeat`. Neither calls destiny (DEF-0105). |
| Cultivation breakthrough | — | `qi` / `body` / `mind` | no | **not built.** `qi_cultivation/advancement.gd:25`, `body_cultivation/api.gd:211`. No oath `FateDef` is authored for the paths (DEF-0106). |
| Counters (`record`) | — | whoever owns the moment | — | **no call site anywhere in `game/src`.** 16 of 17 fates author `counters` (9 distinct ids), every `{verb: counter}` gate is permanently false (DEF-0168, DEF-0181). |
| Item / unique equip | — | undecided | — | **not built**; the relationship is decided by ADR 0135, not implemented. |

**Only three sources exist, and none of them can fire.** The module is internally correct and
entirely unobservable in play. That is the honest state, and it is the reason more internal
work would be wasted.

### 4. A refused earn records nothing

`earn_fate` / `earn_destiny` return the ledger **unchanged** on every refusal — unknown id,
unmet `requires_*`, closed exclusivity group. There is no queue, no pending flag, no deferred
grant, no retry. `QuestGrants` records a refused grant as `unspent` in *its own* return value,
which is the caller's own bookkeeping and not a fate-side record.

So: **a consumer that wants a gate to open must call `earn_*` again once the gate can pass.**
There is nothing to re-drive, because nothing was queued. This is the subtle one — an agent
that assumes a refused earn is remembered will build a consumer that silently never fires.

## Consequences

- The standard for this module is now "enough surface for another feature to use destiny".
  The twelve verbs are the surface; a consumer that needs more folds its read into
  `summary()` or supersedes this ADR.
- `state()` is the save seam, `summary()` is the screen seam, and `gate()` is the content seam.
  A consumer that reaches past any of them into `actor.module_data` or a module internal is
  doing what `tools arch` cannot catch.
- Adding a *consumer* is: declare the dep in `registry.json`, call the facade, add a test.
  Adding an *earn source* is: decide the moment in the owning module, call `earn_*` there.
- The earn matrix is a snapshot; it goes stale silently. Re-measure with
  `Select-String -Path game/src -Recurse -Pattern 'DestinyApi\.earn_'` rather than trusting it.
- Still owed to whoever wires the next source: the `quest` registry entry (a one-line edit),
  and `QuestApi.accept` / `EventApi.set_location` production callers, without which the earn
  path has nothing to fire from.