# 0235 A boss is a committed exchange with one telegraphed turn, not a second script

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0228 (the player's blow), ADR 0197 (the exchange, the rate gate on the
  press), ADR 0074 (a role is a tag, never a branch), ADR 0210 (the telegraph is a deadline)
- Amends: ADR 0197's "`PlayerAdapter.attack` is exercised only by tests"

## Context

ADR 0074 forbade `if role == "boss"` inside damage resolution and gave the correct reason:
three mechanisms that each branch on role are three mechanisms that disagree. But it left the
consequence unstated. **Its "Consequences" section says the cost "belongs in a component, not
a subclass" — and no such component exists.** A boss today is a bigger number plus a tag, and
nothing else:

- `InhabitantDef` has `realm_id`, `base`, `cultivates`, `hostile`, `tags` — no boss
  behaviour field (`inhabitant_def.gd:24-44`).
- `DomainRoles` distinguishes `BOSS` and `MINIBOSS` from `MOB` for placement and for the
  minimap's `tier` chip only (`domain_minimap.gd:265-267`).
- `FightLoop` prices every opponent identically: same spine, same `attack_speed` rate for the
  hero, neutral interval for the opponent (`fight_loop.gd:331-336`).

So the fight a player is asked to read as a *boss* is arithmetically identical to the fight
against a rat with a bigger pool. The number tells the player how long it will take; nothing
tells them what is about to happen.

**How a fight reads, and why "bigger" is not a reading.** A committed exchange — which is
what ADR 0197 settled this game has — lives or dies on three beats, and all three are about
*the player's ability to act on information*:

1. **Telegraph** — something is announced before it can hurt you, and the announcement is
   readable. ADR 0075 and ADR 0210 already own this for hazards; no ADR owns it for a
   duellist. `FightLoop.exchange` currently rolls the opponent's answer **inside the same
   call as the hero's blow** (`fight_loop.gd:344-352`), so the hero cannot know anything
   before it and can never punish anything.
2. **Commit** — the actor who has announced is bound to that choice, so the player who
   correctly read it is rewarded for reading it rather than for having pressed at the right
   moment. Commitment is the only thing that makes a telegraph worth reading.
3. **Punish** — the window where the enemy's committed action cannot land, and hitting in it
   is worth more than hitting anywhere else.

A boss is not "more health". A boss is a fight that **hands the player a decision it can get
right**, and a mob is one that does not. The difference is behavioural and it must not be a
role branch.

## Decision

**A boss is an `Actor` that carries a `BossEncounter` component. The component adds exactly
one thing: a committed turn with a readable telegraph. Everything else — health, damage,
wounds, the sea, the reward — is the same code every other inhabitant runs.**

### The shape

- **`CombatBoot.bind_boss(actor, spec)`** installs a component under a new component id.
  It is the fourth `bind_mechanism`-shaped seam in `app/`, in the same file, in the same
  install order. No new module, no new facade, no new layer.
- **The boss's turn is a two-phase exchange inside `FightLoop`**, so both sides stay real
  `Actor`s and the spine stays the only damage model (ADR 0133):
  - **read** — the component publishes `next_intent`, `telegraph_seconds`, `kind`. This is a
    *read*, and it must be readable one blow before the blow that uses it, or it is not a
    telegraph. It rides `FightLoop.summary()` unchanged — the page already renders the whole
    summary.
  - **commit** — `exchange()` resolves the announced intent, not a fresh roll.
  - **open** — the seconds in which the committed intent cannot land, so a hero blow
    landing inside it is flagged `punish` on the outcome.
- **The three beats map onto what already exists.** `telegraph_seconds` is the *rate gate's*
  vocabulary, not a new constant: a boss's interval comes from its own `Stat.ATTACK_SPEED`,
  and the telegraph is the remainder of that interval. A boss with high `attack_speed`
  telegraphs less; that is the same stat the whole anchor is built on.
- **The spec is authored data on the boss's def**, keyed by realm exactly like ADR 0199's
  vitality. One number — `punish_window_blows`, an integer count of blows — is the whole
  mechanical difference. `1` is a boss you must survive. `3` is a boss with a real opening.

### What a boss is NOT

- **Not a bigger pool.** ADR 0199 already set the pool at `HITS_TO_KILL * BASE_HEALTH *
  RealmDef.power`. That stays and it is not the boss-ness.
- **Not a second damage model.** A boss is resolved by the same `CombatSpine`, the same
  `DamageMechanism`, the same S1-S12. If a boss "needs" its own damage formula, that is a
  mechanism with different authored inputs, which the seam already supports (ADR 0067).
- **Not a role branch.** `role == "boss"` in the spine stays forbidden. The component is read
  for a *timing* fact only, which is the same distinction ADR 0074 drew when it let a role
  reach content and forbade it reaching arithmetic.
- **Not a nameplate.** The distinction the player feels is: a mob's answer arrives, a boss's
  answer was announced. Everything else about a boss — the size, the health bar, the music —
  is presentation over a number, and a number is not a reading.

### How a low-realm cultivator fights a high-realm one without lying about the numbers

This is the load-bearing design question and the answer is in the structure above, not in a
multiplier. **A fight you will probably lose must still be a fight you can lose well.**

- **Nothing about a realm gap is hidden.** The pools are the ladder's own numbers and the
  screen shows both. What changes is that the *decision* is still live: a player who cannot
  win can still learn which telegraph they misread, and the loss writes a wound and a defeat
  onto a ledger (`FightLoop._decide`) rather than a greyed-out number.
- **The punish window is where a weaker player is competitive.** A blow in the window is worth
  more against a bigger pool than the same blow out of it, because the enemy spends the turn
  it could not act in. That is the whole reason a bigger enemy is beatable by a smaller
  player: **not less health per hit, but more of your hits arriving at the only moment the
  enemy cannot answer.**
- **The reward for reading is proportional, so it stays true at every realm gap.** A `1`-blow
  punish window against a 30-blow creature is a rounding error; a `1`-blow window against a
  25-blow creature is the fight. That is correct — an unwinnable fight should not be winnable
  by pattern — but it means the *tier*, not the window, decides whether the fight is winnable,
  and ADR 0219 already made the tier the authored thing a player chooses to attempt.
- **What a weak player gets is the ledger, not the loot.** A defeat is a `CombatDuel` row
  and a fate (`duel.gd`, DEF-0105), so losing to a high-realm antagonist is progression in the
  one currency a run can always pay in.

## Consequences

- **The tag finally has teeth without costing the spine a branch.** ADR 0074's stated cost is
  paid, and paid in the component it named.
- **`FightLoop.exchange` gains a phase**, so ADR 0197's "one exchange is one call" survives
  as "one exchange is one call, and the opponent's half is the announced one".
- **The boss tier data already authored stays untouched.** `LootTier.boss_tables`,
  `LootEncounterDef`, `InhabitantDef.realm_id` — none of them change. The boss spec is one new
  optional field on the *inhabitant* def, defaulting to absent, and an absent spec means the
  component is not installed and the actor is a mob with a big pool. That is the fail-safe.
- **The encounter screen's boss and this boss are two different things** until ADR 0228's
  reward seam closes. `CombatApi.exchange` resolves the run's boss as a dictionary and cannot
  carry a component; a placed boss can. This ADR decides the placed one, and the merge point
  is the reward agent's verb.

## Rejected

- **Give the boss more health, more damage and a name.** Cheapest, and it is what
  `LootTier.vitality` already is. Rejected: it changes how long a fight takes and nothing
  about what the player *does*, and a fight whose every turn is identical is a damage sponge
  wearing a health bar.
- **A second `DamageMechanism` subclass for bosses.** Rejected: it is `if role == "boss"`
  with better manners, and ADR 0067's seam exists so a fourth path costs one file rather than a
  branch.
- **Make the boss's telegraph a `StatusEffect`.** Tempting — the machinery ships and ADR 0210
  already owns the window vocabulary. Rejected on timing: a status is applied *by* a landed
  blow, and a telegraph must be readable *before* one. Making the announcement itself an
  inflicted status inverts the beat.
- **Let the hero dodge.** The anchor excludes it, ADR 0197 records that splitting the turn
  would make the opponent's blow "a second press the player could decline", and nothing here
  reopens that.

## What would change my mind

- Measured evidence that `punish_window_blows` moves win rate at a fixed realm gap in a way
  that is not explainable by variance. If the window is noise, the honest answer is that this
  game has no boss mechanic and a boss is a pool.
- An owner ruling that the fight stays strictly two-sided and un-telegraphed, in which case
  the *tier* is the only boss-ness available and this ADR should be retired rather than
  softened.
