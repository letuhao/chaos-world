# 0236 Winning is a decided verdict, and the zero crossing is the only seam anything else may listen to

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0228 (the stage chain), ADR 0162 (the chip floor), ADR 0089 (statuses are
  session-only and purge on combat exit), ADR 0159 / ADR 0130 (a death costs the soul)
- Coordinates with: ADR 0220 (escrow waits on the death seam)

## Context

**The kill is already computable and is already decided — in two places, with two rules, and
in neither place is it observable to a caller that did not do the arithmetic.**

- `CombatDuelHit.resolve` spends `share * pool.maximum` and returns `defender_slain`
  (`duel_hit.gd:85-97`), then writes the duel ledger and the fate (`duel_hit.gd:220-240`).
- `CombatBoot.duel_blow` does the same through the spine and returns `defender_slain`
  (`combat_boot.gd:623-652`).
- `FightLoop._decide` decides from the health pools **alone**, in one place, and closes the
  loop (`fight_loop.gd:380-384`). Its docblock is explicit: a caller that re-derived the
  verdict would have two rules about when a fight ends, and they would drift on a
  corpse-with-health-left.

**Three things are missing, and they are three different things.**

1. **A kill is not always the zero crossing.** ADR 0162 settled that a *landed* hit always
   pays the shared chip floor, so a fight cannot end by being unable to hurt someone — but a
   **body** fight ends at `health <= 0.0` while a **mind** fight's real currency is the sea.
   `MindDamage` writes `turbulence` and a rupture bleed instead (`mind_damage.gd` effects), and
   a mind opponent can be beaten with its health untouched. So "the health pool reached zero"
   is *a* death predicate, not *the* death predicate.
2. **Nobody outside `combat`/`app` can hear it.** `SoulDeath.is_dead` reads `health <= 0.0`
   (`soul_death.gd:312-316`) and `item_workbench_play.gd` polls it every frame — so the
   **player** death seam exists and works. But there is **no death signal for a non-player
   actor**: `grep` for `slain|death|actor_died` across `game/src` returns only the booleans
   above. Escrow (ADR 0220) is blocked on exactly this, and so is anything else that wants to
   react to a creature dying.
3. **A kill has no outcome word.** `CombatExchange` has `boss_defeated` / `player_lost`
   (`exchange.gd:56-58`); `FightLoop` has `hero_won` / `hero_lost` (`fight_loop.gd:124-126`).
   `CombatDuelHit` and `duel_blow` have a boolean. Three vocabularies for one event, and none
   of them is the one a third module would subscribe to.

## Decision

**Winning is a DECIDED VERDICT, computed once by the layer that spent the pool, published as
one word, and observed by everything else through exactly one seam: the transition of an
actor's health pool across zero.**

### 1. Damage must be able to kill — it already is, and the rule holds

- **The landed hit always spends the chip floor** (ADR 0162). That is what makes a *decisive*
  kill possible without making an immune actor possible.
- **A kill is decided by the pool that was spent**, in the layer that spent it. `FightLoop`
  already owns that rule for a whole fight (`fight_loop.gd:380-384`); `CombatDuelHit` and
  `duel_blow` already own it for one blow. This ADR does not move either. It forbids a fourth.
- **A mind fight is decided by its own currency.** A sea collapse or a rupture bleed past its
  threshold is a kill even at full health, and the verdict must say which pool decided it.
  `CombatOutcome` already carries the per-mechanism effects; the verdict reads them, it does
  not re-derive them.

### 2. The outcome is OBSERVABLE in one word

Every surface that decides a fight publishes the same three values, and a caller branches on
`outcome` and never on a number:

- `outcome`: `""` (ongoing) | `hero_won` | `hero_lost` — **already published by
  `FightLoop.summary()` and `exchange`** (`fight_loop.gd:436-458`). `CombatDuelHit.resolve`
  and `duel_blow` must publish the same two words in place of their bare
  `defender_slain: bool`; the boolean stays for compatibility but is no longer the answer a
  screen reads.
- `decided_by`: `health` | `sea` | `rupture` | `spared` — which pool ended it. **This is the
  one field that makes a mind kill legible** and it is why the boolean was insufficient.
- `opponent_id` / `killer_id`: who is standing and who did it, so a listener does not have to
  be the attacker.

**The existing two vocabularies are NOT to be merged here.** `boss_defeated` is `loot`'s rule
E1 outcome and `hero_won` is the fight's; a caller that needs both reads both. Merging them is
a module change with no owner.

### 3. The seam: exactly one, and it is the zero crossing

**The one thing a third party may listen to is the transition of an actor's `health` pool
across zero.** Not a signal, not a poll, not a callback — the **transition**, because that is
what makes it once-per-death by construction:

- `ResourcePool.change` already clamps at `current + delta`
  (`contracts/resource_pool.gd:29`); a `changed` edge read against `current <= 0.0` is a state, and a
  state cannot fire twice for one death. A signal emitted per `change()` call would fire
  again on every subsequent `pool.change(-0.0)` a status tick makes.
- **Who may listen: `app/`.** It is the only layer that may depend on anything, it already owns
  the frame driver and the death poll, and it already holds the one `Callable` seam pattern the
  repo uses for exactly this (`CombatBoot.set_attack_resolver`, `NpcApi.set_minter`). A module
  that wants to know may **register a callable**, never import anything.
- **A module never learns about death by polling `health`.** `SoulDeath` polls because it is
  `app/` and it already did; a second poller is a second rule about when a fight ends, which
  is the exact failure `FightLoop._decide`'s docblock names.

### 4. What the losing side owes

A decided loss is **a run that stops and a body that is carried out**, and it is written on
the **loser's** ledger — never the victor's:

- **The loser pays, and only the loser.** `CombatDuel.record_defeat` is the one place a fight
  is decided lost and it writes `defeats`, `last_defeat` and the fate
  (`duel.gd:120-131`). A win is a counter; a loss is a history with a body attached.
- **The run is abandoned, and its reward is never minted.** `LootApi.abandon` is rule E4 and
  it discards the in-progress boss only (`loot_state.gd:426-441`). A lost run therefore never
  mints, which is why a defeat is a stake on the run rather than on the account.
- **The loser is walked out whole.** `exchange._answer` restores the player to full vitality
  at the end of the file (`exchange.gd:659`) and `FightLoop` carries no wound forward. A
  boss fight is not a wound that persists — **this is a disclosed thinness, not a rule**, and
  ADR 0076 records it as an open gap.
- **A guardian death is not a death** (`soul_death.gd:127-131`), so a listener must branch on
  `decided_by`, not on the crossing. A body that stopped in a guardian's arms did not earn an
  arrival.

### 5. What I need from the escrow agent, stated rather than invented

ADR 0220 records the real blocker: `loot_state` does not cross the re-embodiment
(`soul_death.gd:253-296` carries only `world_facts` and `destiny_state`). I am **not**
inventing a death system to hang escrow on — it exists, above. What escrow needs from this
ADR's seam is exactly:

1. **one registered callable, called with `(actor, decided_by, killer_id)`**, fired once per
   death, from `app/`;
2. **fired on `health` crossings and on a `sea` / `rupture` death**, so a mind fight is not a
   silent forfeit;
3. **never fired for a `spared` verdict** — a spared opponent is on their feet
   (`duel.gd:174-199`) and forfeiture must not read it as a loss;
4. **the crossing is the payload, not the state**, so a listener cannot double-fire on a
   subsequent zero-delta change.

## Consequences

- **`defender_slain: bool` becomes a compatibility field, not the answer.** Screens branch on
  `outcome`; `decided_by` is what tells a player *why* the fight stopped.
- **A mind fight is legible.** Today a mind duel that ends on a sea collapse reads as "the
  fight is over and I do not know how", which is the same dead surface BL-0210 is about one
  layer up.
- **`FightLoop._decide` is the reference implementation** and must not be re-derived. Any
  second rule about when a fight ends is the defect named at `fight_loop.gd:371-375`.
- **The guard that matters**: a mutation that removes the `_decide` health read must turn a
  test red, and one that makes the crossing fire twice must too (INC-0016: a green guard is
  not a tested guard).

## Rejected

- **A `died` signal on `Actor`.** Rejected: a signal is a callback per emitter and the repo's
  rule is that a death is a *state*, decided by the layer that spent the pool. `Actor` is
  `core/` and may not know a fight exists.
- **Let `LootApi` watch the player's health.** Rejected: `loot` declares no clock and no
  `soul` edge, and `app/` already owns both.
- **Have the loser pay in items, qi or time.** Rejected for now: every currency that could be
  spent belongs to a module this change does not own, and ADR 0076 records the gap honestly. A
  loss that costs nothing is thin, not wrong.
- **Merge `boss_defeated` into `hero_won`.** Rejected: they are two owners' rules (E1's
  payload versus the fight's) and a merge has no owner this ADR could name.

## What would change my mind

- Measured evidence that a third party genuinely needs to know *who* killed something beyond
  the caller — in which case `killer_id` becomes more than a field and a lightweight actor
  ledger is justified on its own ADR.
- An owner ruling that defeats must persist as wounds on the next body. That contradicts
  "walked out whole" and would make a loss cost a body, which is a `soul` decision and not
  mine.
