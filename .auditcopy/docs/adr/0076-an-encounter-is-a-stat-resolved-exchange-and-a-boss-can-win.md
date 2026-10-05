# 0076 An encounter is a stat-resolved exchange, and a boss can win

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0061 (a tribulation is fought), ADR 0022 (damage reduction is flat)
- Resolves: BL-0223
- Supersedes the state ADR 0077 measured: its Context line "`modules/combat/` holds
  exactly two scripts" describes the tree before this ADR landed.

## Context

Nobody had decided whether this game has combat resolution, and the audit behind BL-0223
measured what the absence cost:

- **`core/actor_stats.gd` computes 11 combat stats** and no production code read any of
  them. `RealmScaling.SCALED_STATS` multiplies four of them — `ATTACK_PHYSICAL`,
  `ATTACK_SPIRITUAL`, `DEFENSE_PHYSICAL`, `DEFENSE_SPIRITUAL` — by `RealmDef.power`, the
  1.0-551x authored realm table (ADR 0050). That scaling was already paid for and bought
  nothing.
- **1772 authored content files grant those stats** (`game/data/**/*.tres`,
  `master_option_pool.jsonl`): 358x `attack_physical`, 353x `penetration`, 331x
  `defense_physical`, 327x `evasion`, 290x `crit_chance`, 262x `defense_spiritual`,
  117x `damage_reduction`. Every one is a loot incentive that currently changes no
  outcome.
- **`modules/combat/` was two files and zero callers.** `Shield`'s docstring promised
  "damage depletes the shield before health"; nothing depletes it.
- **`app/player_adapter.gd:156-163`** resolved a target and then executed a comment:
  `# Combat resolution wired by the combat module facade`.
- **No fight could lose.** `LootApi.strike(actor, damage, seed)` took a flat `25.0`
  (`LOOT_STRIKE_DAMAGE`, `item_workbench_app.gd:20`) against 40-520 authored vitality
  (`LootTier.vitality`), 61 tiers, 62 reachable bosses. Nothing in the exchange touched
  the player, so the failure branch the completion bar names was unreachable for every
  boss and every domain.

## Decision

**The game has combat resolution. An encounter is one exchange of two stat-resolved
blows, and either side can win it.**

- **`CombatDamage.resolve_hit(offense, defense, rng)`** is the whole damage model: a pure,
  stateless function over two stat bundles. It returns a **share of the target's own
  pool**, not an absolute number.
- **A share, never a magnitude.** `share = BASE_SHARE * power * (1 - mitigation)`, clamped
  into `[MIN_SHARE, 1.0]`. Because both the boss's vitality and the player's health are the
  pools being spent, the model is realm-neutral by construction: the 551x realm table
  moves both sides together and cannot make an endgame player one-shot a low-realm boss.
  Rejected: raw `ATTACK_PHYSICAL` as damage — the realm table spans 551x and authored
  vitality spans 12x, so that shape makes every boss a one-press kill at high realm and
  every deep boss unkillable at low realm.
- **`power` is a bounded multiplier on the attacker's own numbers**, normalised by
  `REFERENCE_ATTACK` and clamped by `POWER_CEILING`; `mitigation` is
  `defense / (defense + REFERENCE_DEFENSE) + DAMAGE_REDUCTION - penetration_share`,
  clamped by `MITIGATION_CEILING`; and `MIN_SHARE` is the floor that makes a fight always
  terminate in bounded presses. Every constant is named in `combat/damage.gd`. None derives
  from a realm index, and none is a new per-realm scale.
- **A boss's own numbers come from the vitality its band already authors.**
  `LootTier.attack_for` / `defense_for` are `ATTACK_PER_VITALITY` /
  `DEFENSE_PER_VITALITY` times that band's authored vitality, so one authored number
  prices both halves of a fight, a trash mob is weaker in both directions, and **no
  encounter file has to be re-authored**. `LootState._spawn` freezes them into `active`,
  so the profile a fight was priced at cannot move mid-fight.
- **One exchange is one call.** `CombatExchange.exchange(actor, seed_value)` reads the live
  boss through `LootApi.summary`, spends the player's blow through `LootApi.strike` (the
  proven seam, with rule E1's once-only award intact), and — only if the boss survived —
  spends the boss's return stroke on the player's `health` pool. `CombatApi` is a thin
  facade over it, so a later blow-level spine (ADR 0077's build order) adds verbs to the
  facade without touching the exchange.
- **A defeat ends the run.** At zero health the exchange calls `LootApi.abandon`, so the
  in-progress boss resets at full vitality and the reward that was not yet minted is never
  minted. `combat` keeps its own record (`defeats`, `last_defeat`) in
  `actor.module_data["combat_duel"]` (ADR 0027's pattern). The player is carried out at
  full vitality: a boss fight is not a wound that persists.
- **`LootApi.strike` keeps its exact signature.** It is the primitive that spends damage
  on a pool; it is not, and is no longer documented as, the game's damage source.
- **`Shield`, `attach_shield` and `shield` are deleted.** They had zero callers and
  promised absorb semantics nothing honoured. A shield is a stage the spine does not have
  yet, and when it does it is a component in the spine's own slot.

## Consequences

- Nine of the eleven combat stats become load-bearing: `ATTACK_PHYSICAL`,
  `ATTACK_SPIRITUAL`, `DEFENSE_PHYSICAL`, `DEFENSE_SPIRITUAL`, `PENETRATION`,
  `EVASION`, `CRIT_CHANCE`, `CRIT_DAMAGE`, plus `DAMAGE_REDUCTION` (ADR 0022's flat
  fraction, now read). **`ATTACK_SPEED`, `POISE` and `STATUS_RESISTANCE` stay unread and
  this ADR says so**: `ATTACK_SPEED` is a per-second quantity and this exchange has no
  time axis, while `POISE` and `STATUS_RESISTANCE` need statuses that nothing authors.
- A player loses a fight by reaching zero health, and the run — not the account — is the
  stake. **The cost of losing is thin, and that is a disclosed gap**: no item, qi or
  resource is spent on a defeat, because every currency that could be spent belongs to a
  module this change does not own. Making a loss cost something is an open decision.
- **The calibration is provisional, deliberately.** `tools realm_power check` guards the
  shape of the realm table and not its recipe (ADR 0050); the same is true here. The tests
  pin the *properties* — monotone in attack, defense, penetration, crit and evasion;
  bounded by `POWER_CEILING` and `MITIGATION_CEILING`; a share never below `MIN_SHARE`, so
  a fight always terminates — not the exact numbers. Retuning is a one-file edit.
- `combat` now depends on `loot` (`tools/arch/registry.json`): the fight's reward and
  claim lifecycle belongs to `loot`, the resolution belongs to `combat`, `combat` composes
  them through the facade, and `loot` learns nothing of `combat`. The reverse edge is
  forbidden and the arch checker enforces it.
- **Wiring is not done here.** `app/item_workbench_app.gd` still points the loot bridge's
  `strike` at `LootApi.strike`, so a player pressing Strike still spends a flat 25. The
  composition root must re-point it at `CombatExchange.exchange`; the exact edits are
  reported with the change. Until then the mechanic is real and headlessly reachable, and
  the flat path is inert rather than removed, because `LootApi.strike` is the primitive the
  exchange itself spends.
- **Deliberately not decided here:** real-time combat, a scene graph, boss AI, and
  multi-enemy encounters. This is a press-driven exchange, matching the screen that
  already exists.
