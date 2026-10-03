# 0140 The actor schema carries body wounds, so necrosis survives a save

- Status: Accepted
- Date: 2026-10-03
- Precedes: the "`SCHEMA_VERSION` goes 4 -> 5 so wounds persist" promise in ADR 0070
- Supersedes: the "`SCHEMA_VERSION` stays 4" lines in ADR 0089's notes and
  `status/api.gd`, which asserted the number rather than the statuses contract

## Context

ADR 0070 gave the body path a wound ledger: per-meridian severity accumulating in
integrity units, and NECROSIS at `0.25` — deliberately one failed breakthrough's worth,
so a good fighter costs a cultivator a realm. Two properties of that ledger are
irreversible by design. `decay` floors a necrotic channel at `necrosis_threshold` and no
rate drops it below, and `necrotic` is a `bool` rather than a number, so no threshold and
no repair can un-necrose it. `MeridianNetwork.repair_meridian`, through the realm's ADR 0031
recovery item, is the single clearable route ADR 0070 names.

The ledger had that arithmetic and a `to_dict` / `load_from` pair — and `Actor.to_dict`
wrote no key for it. Every save and load reset a body to un-hit. That is not a cosmetic
loss: the save file was the one mechanism that undid ADR 0070's central irreversible
fact, for free, on every load, and it did so silently.

`SCHEMA_VERSION` stayed at 4 while the payload would have needed a new slot, which is the
same ambiguity ADR 0037 recorded for `mind_attempt` in v3: the shape changed without the
version saying so.

## Decision

- **`Actor.SCHEMA_VERSION` is 5.** The wounds ride in their own `body_wounds` payload
  slot, and are excluded from the generic `module_data` loop so they are serialized
  exactly once — the `mind_attempt` precedent, unchanged.
- **The slot is raw data.** Core cannot import `combat_engine`, so `to_dict` reads the
  bound ledger off the `&"body_wounds"` component through `has_method` / `call` and shape
  checks the result; `from_dict` stashes the raw payload in `module_data`; and
  `CombatEngineApi.attach_wounds` rebuilds the typed `BodyWounds`. Core owns the key and
  the version gate, the module owns the meaning.
- **A missing slot stays missing.** `from_dict` follows the file's existing
  `data.get(SLOT, {})` + non-empty-check pattern, so a v4 payload loads as *no wounds*
  and invents nothing. An absent slot is deliberately NOT turned into an empty ledger:
  "this body was never hit" and "this body was hit and every wound decayed" are different
  facts, and an old save must not be made to assert the second.
- **The loader decides what is usable, and it degrades.** A non-dictionary, a
  non-numeric severity and a non-`bool` necrosis flag all read as absent rather than
  throwing, which is the untrusted-input contract `Actor.get_module_data` already states.
  A NECROSIS flag is honoured only when it is a real `bool`.
- **`Actor.statuses` is untouched and still unserialized.** Statuses remain session-only
  (ADR 0089); this ADR does not re-open that, and DEF-0059 tracks it. Three tests that
  pinned the literal `4` were re-pointed at `Actor.SCHEMA_VERSION` so they keep asserting
  what they mean — "statuses do not bump the schema" — instead of freezing the number.

## Consequences

- A necrotic channel stays necrotic across a save, and a restored ledger still floors at
  the necrosis threshold under decay. Both are asserted through the real
  `to_dict` -> `from_dict` -> `attach_wounds` path.
- The composition root owns one call: `attach_wounds` after `Actor.from_dict`. Nothing
  must be flushed before a save, because `to_dict` reads the live ledger.
- The module key exists in three places — `BodyWounds.MODULE_KEY`,
  `CombatEngineApi.WOUNDS_MODULE_KEY` and `Actor.WOUNDS_MODULE_KEY` — because core cannot
  import the module. The round-trip test is what holds the copies to each other.
- `CombatEngineApi` now exposes 12 public methods, exactly `MAX_FACADE_PUBLIC_METHODS`.
  Any further verb on this facade needs a split, not a thirteenth method.
- A save written before this change loses its wounds. That is not recoverable and was
  never recoverable; the loss simply stops being invisible.
