# 0923 the story shape is three content types over one runtime, and a new family declares itself

- Status: Accepted
- Date: 2026-10-08

## Context

The story program needed a SHAPE another feature or a mod can author against without
a refactor. Three questions recur: what is said, what it pays, and who won. Each had
a subsystem or nothing behind it, and each is now content with one runtime.

## Decision

1. **One runtime per content type, and the content is `.tres`, never code.**
   - A **conversation** is `DialogueDef`: nodes, ordered `lines`, `choices` carrying an
     optional `DialogueCondition` and an optional effect. Runtime: `DialogueRunner` over
     the actor's `module_data["dialogue_state"]`, so it resumes across a save.
   - A **reward bundle** is `ChestDef`: weighted `rows` plus `guaranteed`. Opened by
     `ItemsApi.open_chest(actor, chest_id, seed)` — ONE seeded `RandomNumberGenerator`
     drives both the weighted picks and the per-item realization seeds, so the same
     chest at the same seed always pays the same bundle (ADR 0025).
   - A **verdict** is `EventStageDef.resolves = {war_id, winner_id}`: a stage that DECIDES
     another event. `EventApi.advance` collects it and delivers it through
     `EventApi.resolve` AFTER its own write, because `resolve` re-reads and re-writes the
     ledger. Record the stage first, then resolve the contest it decided (ADR 0085: the
     political layer never decides its own winner).
2. **Two authoring doors onto ONE content.** A writer may hand-author the `.tres`, or
   write a Yarn-shaped script compiled by `DialogueYarn` through
   `uv run python -m tools dialogue compile --src x.yarn --npc <id> --id <id> --out
   res://data/dialogue/x.tres`. The compiler is engine-side, so it cannot disagree with
   the runtime; a second interpreter is the failure this pins.
3. **A choice names its own id**: `-> #ask_oath label`. The positional fallback
   (`choice_0`) exists, but a saved press is addressed by id, so reordering options must
   not redirect it (`DialogueChoiceDef`'s own rule).
4. **A reward is a KIND, never a special case.** `QuestDef.GRANT_KINDS` is
   `fate | destiny | item | chest`, and each kind is paid by the module that owns the
   thing. A grant the game cannot deliver is recorded unspent WITH ITS REASON.
5. **A new content family declares itself** in `tools/arch/families.json`
   (`data_dir` + `def_class`). An undeclared folder fails `data audit` by name — the walk
   never silently skips it.
6. **A refusal is named at the boundary of the verb that refuses**, and a screen renders
   the module's own reason rather than an opinion of its own.
7. **A screen for a conversation authors no prose.** Speaker, lines, choice labels and
   refusals are authored content the facade publishes, so one text source serves every
   language and the screen adds no i18n key.

## Consequences

- A mod or a later feature defines its own conversation, chest, verdict or reward by
  dropping a `.tres` into a declared family — no GDScript and no new facade verb.
- Adding a content TYPE is a registry line plus a schema row, not a subsystem.
- The cost, stated plainly: these three types must not grow a second runtime. A second
  chest opener, a second dialogue interpreter, or a second place a war's winner is
  decided are each the defect this record exists to refuse.
- Shipped examples are the shape's proof: `game/data/dialogue/elder_wei_intro.yarn`
  (compiled to its `.tres`), `game/data/chests/field_camp_supplies.tres`, and
  `tournament_of_the_spirit_peaks`' final stage resolving `war_of_the_nine_fords`.
