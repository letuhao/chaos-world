# 0220 Escrow is a deposit on a delivery the run has not finished, and it waits on the carry seam

- Status: Accepted
- Date: 2026-10-05
- Re-frames: BL-0253 (its stated blocker no longer exists; a different one does)
- Depends on: ADR 0130 (a death costs the soul and never the world)

## Context

BL-0253 defers escrow — drops banked personally at defeat and converted only on a clean
exit, lost on death — because "there is no actor-death signal, player-death handler or
hp-kill path anywhere in `game/src`".

**That is no longer true, and the deferral's premise is stale.** `app/soul_death.gd` is a
complete death resolver: `SoulDeath.is_dead` reads `health <= 0.0`
(`soul_death.gd:312-316`), `SoulDeath.resolve` spends a guardian or damages the soul
(`:131-187`), and `app/item_workbench_play.gd:254-269` polls it every frame. ADR 0130
accepted it and its `soul_died` world fact ships.

So the blocker is not "death does not exist". It is narrower and sharper, and it is a
**carry** question:

**A re-embodiment mints a NEW `Actor` whose `module_data` is empty** — measured and
recorded in `soul_death.gd:204-210`, where a probe read `after_swap_on_new_body=0`. Only
two ledgers cross the swap today: `world_facts` (`_carry_facts`, `:253-259`) and
`destiny_state` (`_carry_destiny`, `:289-296`), both under ADR 0181's rule that the soul
owns them.

`loot_state` is on `actor.module_data["loot_state"]` (`loot/api.gd:31`). **It is not
carried.** So today a death silently destroys every unclaimed reward and every cleared-band
ledger the player had — which is not the "one-shot per band" of ADR 0219, it is a
data-loss bug wearing the costume of the rule.

## Decision

**Escrow is the right mechanic and it is BLOCKED — but on the carry, not on the death
event. This ADR designs the seam escrow needs and records the exact precondition.**

**Escrow, when it lands:** a drop realized at defeat time is **held in escrow**, visible
and counted, and converts to the inventory on a clean exit. Death forfeits escrow. This is
a *bargain* and that is the whole point: a player who is carrying three unrealized relics
and one wrong turn has a decision they did not have when the relic was an ordinary row.

**The seam escrow needs is a `loot` -> death edge that does not exist and must not be
invented here.** `loot` declares `[contracts, core, items, status]`
(`loot_content_tables.gd:26`); a `loot -> soul` reference is a new dependency the owner
does not grant for a deferred feature.

**The precondition, stated precisely — all four must hold before escrow is buildable:**

1. **`loot_state` rides the re-embodiment.** It must join the two ledgers
   `_carry_facts` / `_carry_destiny` already carry, or the death handler must name it as a
   third. Until it does there is no correct "after death" state to escrow from, so escrow
   is unbuildable *and* un-testable.
2. **An escrow is a STATE, not a boolean.** `escrowed | converted | forfeited` per drop,
   not "was it picked up" — `LootRewards.build` already realizes at defeat time
   (`loot_rewards.gd:8-12`), so the drop is an object before it is carried.
3. **Forfeiture is not `abandon`.** `LootApi.abandon` is rule E4 and is tested: it
   "discards the in-progress boss, never a reward" (`loot/api.gd:141-142`). Escrow must
   **not** be built by inverting it. It is a third terminal state with its own ledger row.
4. **An owner ruling on the carry.** `loot_state` is a *progress* ledger, not a soul
   ledger, so whether it crosses a body swap is ADR 0181's question and the owner's call.

**Decided now, so the deferral costs nothing:** the tri-state shape above is the design;
`LootApi.extract` is hoisted out of `pickup` first (BL-0253's free piece); and the missing
carry is a defect in its own right that must be filed whether or not escrow ever lands —
it is what makes BL-0253 *true today* rather than merely deferred.

## Consequences

- **BL-0253's premise is corrected**: death exists (ADR 0130), and the blocker is the
  carry. A future agent must not re-derive "there is no death event" — it is in
  `app/soul_death.gd` and it is on the frame path.
- Escrow stays **deferred**. This ADR does not author it and does not unblock it; it
  states the four preconditions so the next attempt starts at the right place.
- The loot module grows no dependency. When escrow lands, the death handler (which is
  already a composition-root concern with every dependency injected, `soul_death.gd:6-15`)
  is the natural caller — `app/` may depend on anything, so **the edge is `app/ -> loot`,
  not `loot -> soul`.**
- ADR 0219's one-shot-per-band is unaffected: escrow changes *when* a drop is carried, not
  *whether* a band restocks.

## Rejected

- **Inverting rule E4 to make escrow.** Rejected explicitly by BL-0253 and correctly: E4
  says abandon never discards a reward, which is the property that makes abandoning safe.
  Escrow is a different verb with a different ledger row.
- **Building a minimal death signal so escrow can be wired now.** Rejected: this is
  exactly the "invent a death system to hang it on" that BL-0253 warns against. A death
  signal is a combat-spine decision (BL-0209/BL-0210) owned elsewhere — and one already
  exists, which is a reason to use that one rather than mint a second.
- **Making escrow a loot-module feature with its own death polling.** Rejected: `loot`
  declares no clock and no soul edge, and `app/` already owns the frame driver and the
  death poll.