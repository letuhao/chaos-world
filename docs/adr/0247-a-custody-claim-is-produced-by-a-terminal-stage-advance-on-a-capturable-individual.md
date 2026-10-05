# 0247 A custody claim is produced by a TERMINAL stage advance on a capturable individual, and the screen learns the subject through an injected subject-listing seam

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0002 (inject the constructor), ADR 0067 (one spine, one seam), ADR 0077 /
  ADR 0092 (an npc is tracked or not, never a subclass), ADR 0085 (a conflict declares sides
  and a prize), ADR 0089 (statuses are session-only), ADR 0104 (a captive is a custody claim),
  ADR 0143 (a UI program reaches `app/` through a bridge of callables), ADR 0101 (a world object
  persists in an injected store), ADR 0226 (a shipped piece of content must be reachable from a
  catalog entry), DEF-0310
- Resolves: DEF-0310

## Context

`custody_screen.gd` ships routed, bound, and green on 220 assertions. Its primary verb still
cannot be pressed by a player, and the reason is not a bug:

- `stage_capture` (`custody_screen.gd:171`) and `stage_transfer` (`:205`) are the only doors into
  capture and transfer, and a grep of `game/src` finds the two declarations plus the screen's own
  `clear()` (`:232`, `:238`). Nothing else stages a beat.
- The capture control is gated on `_capture_subject != ""` (`:662`), a field nothing in production
  sets, so `ActionSet.request` refuses the press before `act_capture` is ever reached.
- The screen says so itself (`:31-38`): *"ADR 0104 leaves capture **conditions** to the caller."*

**This is UNDEFINED, not UNBUILT.** ADR 0104 decided what a captive *is* — a claim on a subject
def id, held by an `OwnerRef`, carrying a count of periods — and deliberately declined to decide
what *produces* one. So the page cannot fire, and no failure anywhere reports that: a state the
gates are silent about, because silence is exactly what "deliberately out of scope" looks like.

Four producers were weighed. What killed each one is quoted from the tree, not from taste.

**A defeated actor reduced to non-terminal capture — killed by its own threshold.** `combat`'s
only outcomes are `OUTCOME_BOSS_DEFEATED` and `OUTCOME_PLAYER_LOST`
(`combat/exchange.gd:56,58`), both terminal, and `CombatApi.spare` (`combat/api.gd:148`) exists
precisely because `CombatDuelHit.resolve` could only end a fight two ways. A capture threshold
would be a stat check invented outside the damage spine — the thing ADR 0077 records this program
paying for: *"five Accepted ADRs describing a spine … and not one of the named symbols existed"*.
It also has nowhere to live: ADR 0085 says the political layer *"never calls combat, never reads a
combat stat"*, and `custody` declares `["contracts", "core", "economy"]` with no `combat` edge. So
the threshold would have to be authored twice or invented here, and either way it is a second
authority on combat. **It belongs in `combat`, not here** — recorded below as a later decision.

**A decided conflict — killed by arithmetic, not by architecture.** ADR 0085 makes this the most
consistent candidate: a prize is declared up front and is `ownership | recognition | tribute`, and
a prize that takes a person should write a claim rather than an item. But ADR 0245 has since
answered the module itself, and its prize is a closed `{prize: ownership|recognition|tribute}`
scoped to a **resource node** and paid by `HoldingsApi.apply_prize`. There is no person in that
shape, and adding one means inventing a second prize kind in a module another agent owns and is
building now. The integration point is still recorded below, because it is right; it is just not
where the button gets its subject.

**An authored encounter — kept, and it is the answer.** Cheapest and fully mechanical: the game
already owns a content-authored fact about every individual it has met, the **stage ladder**, and a
stage is authored by id with a `terminal` flag (`npc_stage_def.gd:17,48`). "This one can be taken"
is therefore a property of the cast, not a computed stat, and authoring it costs a `.tres` edit.

## Decision

**A custody claim is produced by a TERMINAL STAGE ADVANCE on an individual whose def names a
custody term. The subject list is an authored read of the cast's capture terms, handed to the
screen as an injected `Callable`.**

- **The producer is `NpcApi.advance_stage` reaching a `terminal` stage on a def that authors a
  custody term.** It emits nothing itself; `app/` subscribes to `NpcEvents.presence_changed`
  (npc, with `source`) and only where that signal names `retired` — the one presence value that
  means *finished* (ADR 0092). A retirement caused by a fight is a story beat; a retirement
  authored with a term is a capture. The module stays free of `custody` entirely.
- **The capture term is AUTHORED on the `NpcDef`, as a `term_id` and a count of `periods`,** on
  the closed shape `{term_id: StringName, periods: int}`. An individual that authors nothing is
  **not capturable** — not "capturable with a default", *not capturable at all*. So capturability
  is content, and content cannot accidentally ship a page whose primary verb is a free grab.
- **`NpcApi.capturable()` publishes the read model**, as primitives only:
  `{subject_id, subject_kind, term_id, periods}[]`, sorted by `subject_id` — every authored
  individual in the catalog whose def carries a term, whether or not the player has met them.
  Sorted, because "a dictionary's iteration order is not an order a player can be shown twice" is
  the `CustodyScreen._sorted_views` discipline applied one layer down.
- **`CustodyScreen` gains ONE seam, `bind_capture_options(Callable)`**, reached from the
  composition root at the route mount — ADR 0143's shape, and the same one `ForageScreen
  .bind_harvest` and `QuestScreen.bind_quests` use. **It is not a verb.** It answers "what may be
  taken", which the module is the only layer that can answer because the module owns the catalog.
  The screen still calls `CustodyApi.capture` by bare name (`custody` is in `rules.UI_MODULES`),
  so this arm of the composition root is exactly one `screen.call` line and nothing else.
- **`stage_capture` is retained verbatim** and remains the only door into capture. The seam does
  not write a claim; it fills the four fields it would need. A player still never types an id.
- **The screen offers the list through its existing pick language,** `select_capture_subject` on the
  id the seam published, and publishes `available`, `available_count`, `available_ids`,
  `capture_options_wired` and `staged_capture` through `summary()`. `ui_accept` gains a SECOND arm:
  a claim this hero holds is still ended by `Accept`, and a subject with no claim is taken by it.
  **The claim arm stays first**, because `act_capture` deliberately leaves the beat staged so a
  refused press keeps its cause — which means a captured subject is still armed afterwards, and a
  capture-first `Accept` would read as one verb forever and refuse `already_captive` where the page
  meant release. Both verbs are reachable from the keyboard alone; neither swallows `ui_cancel`.

## Why a retirement rather than a defeat

A defeat is a number; a retirement is a **fact about an authored individual**, and it is the only
one of the three producers that needs no new authority anywhere.

- It is **already emitted**: `NpcApi.advance_stage` emits `presence_changed(npc_id, retired)`
  when a terminal stage is entered (`npc/api.gd:328`). The seam needs no new module method to
  produce it.
- It is **already the right shape**: `NpcPresence.RETIRED` is *"Story-complete or dead. Never
  spawns again, and the entry stays as the trace"* — a terminal fact, not a health bar.
- It **never needs a threshold**: the author's stage ladder *is* the threshold. A minor mob with a
  ladder that ends at a terminal stage is capturable; a cast member with no terminal stage is not.
- It **never needs an `rng`**, never reads a combat stat, and never enters `custody` from `npc`.
  `custody` keeps `["contracts", "core", "economy"]`; `npc` gains no edge; `ui` gains no module
  reach beyond the bare `CustodyApi` it already had.
- It **cannot smuggle in prose**: the term is `{term_id, periods}`, two mechanical ids/counts, so
  ADR 0104's "no `description`, no `flavor`, no `display_name`" holds on the def and on the record
  identically.

**And a terminal stage is the only ladder end that is honest.** `NpcApi.advance_stage` refuses
`stage_regression`, so a retired individual is one-way; `NpcApi.spawn` refuses a retired id
(`npc/api.gd:166`). Once captured, the subject cannot respawn as itself and the claim's history
reads as history — which is ADR 0104's release rule made true by the cast rather than by a rule
invented here.

## Consequences

- **`NpcDef` gains `capture_term: StringName` and `capture_periods: int`.** Both default empty, so
  every existing `.tres` is unchanged and no individual is capturable until one is authored. The
  first authored capturable is `drifter`, on a four-period term: an untracked, unnamed-by-anything
  def with no stage ladder, which is exactly a body a world can plausibly have taken.
- **`NpcApi` publishes `capturable()` as its ninth of twelve public methods** — under the
  `MAX_FACADE_PUBLIC_METHODS` cap, and not a verb that exists only for the UI: the same read model
  a quest gate, an encounter script or a save-audit would need, in the same primitives-only shape
  `presence_here` and `summary` already use. **`custody/api.gd` gains NO method** — it is already
  at twelve, and it needed none: `capture` was correct and is unchanged.
- **`EconomyBoot` does not own this seam.** It is the `custody` installer and ADR 0104 gave it
  the subject minter, so putting a `npc`-reading read model there would build `economy -> npc` or
  a lambda over a static (the access-violation shape `NpcBoot._install_event_seams` documents).
  `app/` is where `npc`, `ui` and `custody` may all be named at once, so **the composition root's
  route arm installs it**, one `screen.call` line, beside the default `setup(actor)` it already
  passes this route.
- **The integration point with `conflict` is DESIGN, and imports nothing.** ADR 0245's prize is a
  closed `{prize: ownership|recognition|tribute}` scoped to a resource node and paid through
  `HoldingsApi.apply_prize`. When its owner decides a prize may name a person, the call is
  **`CustodyApi.capture(actor, subject_id, "npc", holder, term_id, periods)` — nothing else**,
  and the conflict module takes no `custody` dependency to make it: the CALL SITE is in `app/`,
  which is the only layer allowed to name both (`registry.json` carries `conflict ->
  ["contracts", "core", "holdings"]`, and `custody` gains no edge). Nothing here is gated on that
  decision, and the ADR above does not read it or wait for it.
- **A capture beat armed by the seam is ADVISORY until the press.** `act_capture` reads the four
  staged fields and forwards them; the producer still decides. A player may stage a subject the
  cast says is capturable and press, and the claim opens — which is why ADR 0104's rule that the
  module never computes the CONDITION is preserved rather than moved: the seam supplies the
  question's *subject list*, not its answer.
- **A term is an authored COUNT, never a price, and never a stat.** There is no `RARITY_WEIGHT` on
  a person (ADR 0104), no realm scaling (ADR 0050), and no `settle` against a claim the holder
  never owed. `periods` defaults to `1` rather than `0`, so a half-authored def is a one-period
  claim rather than a termless grab — the direction that fails as `no_terms` rather than as a
  free capture.
- **Out of scope, named honestly:** a capture threshold in `combat` (recorded below), a subject
  released by an escape (ADR 0104 already routes that to `combat`, then `release`), a market for
  claims (that would make `market` depend on `custody`), a `PlayerDef` for the closed `player`
  subject kind, and a durable world store for `custody`, which inherits ADR 0101's own recorded
  debt unchanged.
- **The other two producers stay rejected with their reasons, and one of them stays rejected in
  writing.** A decided conflict remains the *most consistent* producer on the ADR 0085 reading and
  is the right long-run answer for an institutional prize; it is not wired, because its module
  does not exist in shipped code and its prize shape is closed against a person. A capture
  threshold belongs in `combat` on a future ADR, where the single damage spine already lives.