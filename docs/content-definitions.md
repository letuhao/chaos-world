# Content Definitions: Quest, Event, Story

Authoring reference for the three progression-shaped content families, and how a mod adds
them. This file is about **content data**. For manifest fields, load order, and overlay
rules see [`modding-guide.md`](modding-guide.md).

Read this before writing a `.tres`. Every rule below is enforced by a tool or a test, so a
guess costs a red gate rather than a silent bug.

---

## 1. The three families, and what each one is FOR

They are not three difficulties of the same thing. Each answers a different question, and
using the wrong one is the most common authoring error.

| Family | Question it answers | Who starts it | Who ends it | Owns state? |
|---|---|---|---|---|
| `QuestDef` | "one thing for the player to DO" | an offer, a gate, or code | all non-optional steps satisfied | yes, quest ledger |
| `EventDef` | "one thing HAPPENING in the world" | a trigger, on its own | a stage resolves or it expires | yes, world state |
| `StoryDef` | "in what ORDER, and what must be true first" | never forced | derived from gates | **no** |

A story holds no gameplay. It is a ladder of gates over the other two. If you find yourself
putting a reward, a beat, or a fact write on a story chapter, it belongs in a quest.

### Story owns no state, on purpose

`StoryDef` and `StoryChapterDef` have no persisted field and no write verb. Whether a
chapter is open, done, or blocking is recomputed from gates against state another module
already owns. Three consequences you must design around:

- A story needs no save schema and cannot drift from the quest it waits on.
- A chapter whose completion gate was satisfied **before** the chapter opened reads done the
  instant it opens. That is correct: the world already remembers it.
- An unmet gate **hides** content; it never blocks play. The main story must stay ignorable
  (BL-0068), so there is no code path here that can stop a player.

---

## 2. Shared vocabulary: the requirement language

`QuestDef.requirement`, `EventDef.trigger`, `EventStageDef.requires`, `StoryChapterDef.requires`,
and `StoryChapterDef.completion` are all the **same shape**: either `{}` (empty) or one
`{verb: ..., ...}` Dictionary.

### The shape

```gdscript
{}                                              # ungated / always true
{"verb": &"fact", "id": &"some_fact", "need": 3}  # one requirement
{"verb": &"all_of", "of": [ {...}, {...} ]}       # composite over children
```

`{}` means "no gate". It does **not** mean "false". A chapter with `requires = {}` opens as
soon as the ladder reaches it, which is the right shape for chapter one.

### Verbs available to story gates

`StoryGate` (`game/src/modules/story/story_gate.gd`) reads exactly these:

| Verb | Reads | Through |
|---|---|---|
| `quest_done` | the quest ledger's completed set | `QuestApi.summary(actor)` |
| `fact` | the shared world fact ledger | `WorldFact.count(actor, id)` |
| `has_fate`, `has_destiny`, `counter`, `tagged` | destiny state | `DestinyApi.gate` (delegated verbatim) |
| `all_of`, `any_of`, `none_of` | composites over children | recursive |

`quest_done` is the only verb story contributes. `fact` is read through the ledger's own
reader, and every destiny verb is handed to `DestinyApi` unchanged, so this repo keeps one
fate evaluator instead of two that answer slightly different questions.

Quest and event gates have their own verb sets per module. Check
`game/src/modules/<module>/<module>_gate.gd` for the constants before using a verb; there is
no single global grammar.

### Refusal is not "unmet"

A gate returns `{ok, reason, unmet}`. Two outcomes must never be confused:

- `reason: "unmet"` — a player being told *not yet*. Normal.
- `reason: "unknown_verb"` or `"malformed"` — a **content bug**. Your `.tres` has a typo.

A gate that returned `unmet` for its own typo would make broken content look like
progression, so it refuses closed and names the offending verb instead.

---

## 3. `QuestDef` — one thing to do

`game/src/modules/quest/quest_def.gd`, steps in `quest_step_def.gd`.
Data: `game/data/quest/quests/*.tres`. Family key: `quests`.

### Fields

| Field | Type | Notes |
|---|---|---|
| `id` | `StringName` | stable. A rename is a content break, not a label edit |
| `display_name` | `String` | i18n slug, never prose |
| `description` | `String` | i18n slug |
| `kind` | `StringName` | `authored` \| `systemic` \| `emergent` |
| `tier` | `int` | ordering / difficulty band |
| `requirement` | `Dictionary` | gate to accept. `{}` = always acceptable |
| `fate_gate` | `Array[StringName]` | fate ids this quest requires |
| `steps` | `Array[QuestStepDef]` | the work |
| `grants` | `Array[Dictionary]` | the pay. `{kind, id, amount}` |

The three `kind`s are ONE shape, deliberately (BL-0053). A reader must not branch on `kind`.
`authored` is hand-placed content, `systemic` is generated from world state, `emergent` is
what fell out of play. The field tells a panel how to present it, nothing more.

### Steps

A step is satisfied by a **fact in the world ledger**, not by a quest call:

```gdscript
step_id = &"account_named"
fact    = &"household_heir_registered"
need    = 1
optional = false
```

This is the load-bearing design: the quest module has **no write verb**. Something else in
the world (combat, hunting, cultivation, an npc interaction) records the fact, and the quest
notices. That is why a systemic quest can be completed by play nobody authored.

`optional: true` steps do not gate completion. Use them for flavor objectives.

### Grants

`{"kind": &"fate", "id": &"ancestral_debt_unpaid", "amount": 1}`. Kinds are the ones
`QuestGrants` implements; read `game/src/modules/quest/grants.gd` before inventing one. A
grant naming content that does not ship is a content bug and a test will say so.

### Real example

```
game/data/quest/quests/the_account_left_open.tres
```

One step, gated on the fact `household_heir_registered`, paying a fate. Read it before
writing your first quest; it is the smallest correct shape.

---

## 4. `EventDef` — one thing happening

`game/src/modules/event/event_def.gd`, stages in `event_stage_def.gd`.
Data: `game/data/event/**/*.tres`. Family key: `events`.

### Fields

| Field | Type | Notes |
|---|---|---|
| `id`, `display_name`, `description` | | as above, slugs for the strings |
| `kind` | `StringName` | event category |
| `trigger` | `Dictionary` | requirement language. Starts the event |
| `location_id` | `StringName` | where it happens |
| `on_enter` | `Array[Dictionary]` | beats emitted when the event opens |
| `stages` | `Array[EventStageDef]` | max `MAX_STAGES` = 8 |
| `pay` | `Array[Dictionary]` | resolution rewards |

A stage carries `stage_id`, `display_name`, `requires`, `on_enter`, `duration_periods`, and
`resolves`.

Event vs quest: an event runs whether or not the player engages. A quest waits to be
accepted. If your content needs the player to opt in, it is a quest.

---

## 5. `StoryDef` — the ladder

`game/src/modules/story/story_def.gd`, chapters in `story_chapter_def.gd`.
Data: `game/data/story/stories/*.tres`. Family key: `stories`.

### `StoryDef` fields

| Field | Type | Notes |
|---|---|---|
| `id` | `StringName` | unique across stories |
| `display_name`, `description` | `String` | i18n slugs |
| `synopsis` | `String` | i18n slug for the codex blurb |
| `optional` | `bool` | default `true`. See below |
| `entry_chapter` | `StringName` | must name a chapter this def authors |
| `chapters` | `Array[StoryChapterDef]` | authored order, cap `MAX_CHAPTERS` = 24 |

**`optional` is what makes the main story ignorable.** When `true`, nothing may force a
chapter: the ladder only ever *offers* what its gates have already unlocked, and a player who
never accepts is playing the same world. `false` marks the main spine, which may be surfaced
harder, and is still never a wall.

**`entry_chapter` is an id, never position zero.** Falling back to `chapters[0]` would be a
guess about where a story opens, which is the one guess an author cannot debug. Same reasoning
as `DialogueDef.entry_node`.

**`chapters` is the spine, and the spine is positional.** `StoryApi.progress()` starts at
`entry_chapter` and walks the array in order, checking each *next* chapter's `requires`; it
stops at the first gate that does not pass. So the array order **is** the play order for the
main line, and gates are a stopping condition, not a router.

Alternatives are visible through `offered()`, not `progress()`. `offered()` evaluates every
chapter's `requires` and `completion` independently, so two chapters gated on the same
predecessor both show up as open. That is how you author a branch: two chapters with the same
`requires`, and a later chapter gated on `any_of` them. `progress()` will report whichever one
sits next in the array, so put the branch alternatives adjacent to each other and gate the
converging chapter on `any_of`.

### `StoryChapterDef` fields

| Field | Type | Notes |
|---|---|---|
| `chapter_id` | `StringName` | unique inside its own story |
| `display_name`, `description` | `String` | i18n slugs |
| `requires` | `Dictionary` | the gate that OPENS this chapter |
| `completion` | `Dictionary` | the gate that says it is DONE |
| `dialogue_id` | `StringName` | optional conversation to start |
| `is_ending` | `bool` | a terminal chapter |

A chapter has **no `on_enter` beats and records no fact**. A chapter opening is not something
the world *did*; it is where the player has got to. That is narrative state, not a world fact.
Story READS. Quests, events, combat, and npc tallies are what WRITE.

`completion` is almost always `{verb: &"quest_done", id: <quest_id>}`: the quest is the unit of
authored player action, so the chapter finishes when the quest does.

### The asymmetry, because it decides which verb to use

A **quest step** reads the fact ledger, so a quest can be satisfied by anything the world
remembers. A **story chapter** reads the quest ledger, so a chapter can be finished by anything
the player was handed. That difference is authored progression vs emergent progression: a
chapter gates on a quest, a systemic quest gates on a fact.

### Worked example

```gdscript
# StoryDef: id = &"the_broken_seal", optional = true,
# entry_chapter = &"rumor"

# 1 — opens immediately, done when the player finishes the intro quest
chapter_id = &"rumor"
requires   = {}
completion = {"verb": &"quest_done", "id": &"ask_about_the_seal"}
dialogue_id = &"village_elder_intro"

# 2 — opens as soon as chapter 1 is done
chapter_id = &"descent"
requires   = {"verb": &"quest_done", "id": &"ask_about_the_seal"}
completion = {"verb": &"quest_done", "id": &"enter_the_undercroft"}

# 2b — a BRANCH: same gate as `descent`, so both open together
chapter_id = &"bribe"
requires   = {"verb": &"quest_done", "id": &"ask_about_the_seal"}
completion = {"verb": &"fact", "id": &"undercroft_bought_off", "need": 1}

# 3 — needs either branch, plus a fate the seal quest granted
chapter_id = &"seal"
requires   = {"verb": &"all_of", "of": [
	{"verb": &"any_of", "of": [
		{"verb": &"quest_done", "id": &"enter_the_undercroft"},
		{"verb": &"fact", "id": &"undercroft_bought_off", "need": 1}]},
	{"verb": &"has_fate", "id": &"seal_touched"}]}
completion = {"verb": &"quest_done", "id": &"reseal_the_breach"}
is_ending  = true
```

`descent` and `bribe` are alternatives: both open on the same gate, so `offered()` shows both.
`seal` opens when *any* route is taken **and** the fate exists. Note the ordering rule: keep
alternatives adjacent in `chapters`, because `progress()` walks the array positionally and
reports the first one whose gate passes.

---

## 6. The `.tres` format, and the trap that eats a day

Text resources are authored by hand or by tool, and one Godot 4 rule bites both:

**A typed `Array` field must be assigned a typed array literal.** An untyped `Array` assigned
to `Array[Dictionary]` is a **runtime** type error, and it is fatal in the worst way: it aborts
the builder before its `return`, so the caller installs a `null` definition and every later
read answers `unknown_*`. A fixture that silently returns null looks exactly like a module with
no catalog.

In a `.tres`, that looks like this (from a shipped quest):

```
steps = Array[ExtResource("2_step")]([SubResource("QuestStep_account_named")])
grants = Array[Dictionary]([{"kind": &"fate", "id": &"ancestral_debt_unpaid", "amount": 1}])
```

Both arrays are spelled with their element type. Copy that. In GDScript, build
`Array[Dictionary]` element by element rather than assigning a literal `[]`.

Same trap in reverse: `some_array as Array[Dictionary]` on a plain `Array` returns **null**, not
a converted array. Copy row by row if you must narrow a type.

Other format rules:

- `display_name` / `description` / `synopsis` are i18n slugs
  (`LOC_QUEST_<ID>_DISPLAY_NAME`), never prose. Every string the player reads goes through
  `uv run python -m tools i18n extract`.
- Ids are `&"snake_case"` StringNames. A rename breaks saves and any gate naming it.
- Do not put `res://` paths in docstrings of module code: the arch detector scans raw text for
  `res://` including comments.

---

## 7. Adding content as a mod

### Overlay existing content

Declare the family root and the id field, then ship a `.tres` with the same `id`:

```json
{
  "id": "my_seal_story",
  "version": "1.0.0",
  "priority": 10,
  "requires_api": 1,
  "overrides": ["the_broken_seal"],
  "content_roots": [
    {"family": "stories", "dir": "content/story/stories"},
    {"family": "quests",  "dir": "content/quest/quests"}
  ]
}
```

- Base game scans first; mods overlay in load order; later roots win.
- An id collision **requires** the id in `overrides` or boot aborts with
  `undeclared_override`.
- `id_field` names the def property holding the id when it is not `"id"`. For these three
  families the id field is `id`, so you do not need it.
- Without the correct `id_field`, content is **silently invisible** (ADR 0240). If your story
  does not appear, check this before anything else.

### Add new content

Same `content_roots`, no `overrides`. New ids just join the catalog.

### React to story progress

Story publishes no state, so subscribe to the quest, not the ladder:

```gdscript
var ids := StoryApi.stories_for_quest(quest_id)
if ids.is_empty():
    return   # this quest is outside every authored story; reach no gate at all
```

`stories_for_quest` is the cheap filter: it walks authored content only, bounded by the chapter
cap, so a quest completing outside every story costs one empty array.

### The read model

Everything a panel needs, primitives only. No `Resource` and no `Actor` crosses the boundary
(ADR 0114).

| Call | Returns |
|---|---|
| `StoryApi.offered(actor)` | `Array[Dictionary]` of `{story_id, chapter_id, dialogue_id, display_name}` |
| `StoryApi.progress(actor, id)` | `{known, story_id, chapter_id, done, open, blocked_by, chapters_seen}` |
| `StoryApi.is_finished(actor, id)` | `bool` |
| `StoryApi.summary(actor)` | codex read model, primitives only |
| `StoryApi.problems()` | authored content bugs, as strings |

A chapter is **OPEN** when its `requires` passes and its `completion` does not. That is the only
definition this module uses. `blocked_by` carries the unmet rows of the gate that would have
opened the next chapter, so a panel can say what the story is waiting on without re-deriving the
grammar.

**`done` is story-level, not chapter-level.** `progress().done` is true only when the walk has
reached a chapter with `is_ending = true` *and* that chapter's `completion` gate passes. A
non-ending chapter reads `done: false` forever, however its own gate is answered. To ask "is this
chapter finished", evaluate its `completion` through `StoryGate` or read `offered()`. This trips
people up, so if you need per-chapter completion in a panel, that is the call to make.

### Module rules that apply to all three families

- Reference another module through its `api.gd` facade **only**. Naming another module's
  `Catalog` or `State` class from your module is an undeclared dependency edge, even when it
  resolves.
- `QuestApi` exposes no write verb. You cannot complete a quest from a story, a panel, or a mod
  entry point. Record the fact; let the quest notice.
- A mod cannot change layer rules, the loader, or the locked skeleton (ADR 0184).

---

## 8. Author checklist

Run these before you call content done. Each one is a gate that will fail you.

1. `uv run python -m tools i18n extract` then `i18n check` — every player-facing string is a
   slug **and** that slug resolves. A new content family needs a catalog at
   `game/locale/<owner>.tres`, a `Translation` resource with `locale = "en"` and one row per key.
   Locale files are loaded by directory scan, so dropping the file in registers it; there is no
   list to append to. `extract` will NOT create the file for you, and it assigns keys rather than
   resolving them, so hand-authored slugs need hand-authored rows.
2. `uv run python -m tools arch` — facade-only references, no boundary violations. Adding a
   module also means mirroring its deps into `BASE_DEPS` in
   `game/src/modules/mods/module_registry.gd` (static mirror of `tools/arch/registry.json` with
   layer deps stripped) or the checker fails on drift.
3. `uv run python -m tools test --suite story` (and `quest`, `event`) — content tests read the
   **real** `res://data/` tree, not fixtures. A malformed `.tres` goes red here.
4. `StoryApi.problems()` returns `[]` for your story. It walks the same verb vocabulary, so a
   typo inside a nested `all_of` is caught by a tool rather than by a player failing to open a
   chapter.
5. Every `quest_done` id you name actually ships, and every `fact` id is written by something.
   A gate on a fact nobody records is a chapter that never opens.
6. `entry_chapter` names a chapter in `chapters`.
7. No chapter count above `MAX_CHAPTERS` (24), no event stage count above `MAX_STAGES` (8).

`tools fmt <your paths>` and `gdlint <your paths>` are scoped and fast; run them on your own
directories rather than the whole repo, which reformats other people's in-flight work.

---

## 9. What NOT to do

- **Do not put rewards on a story chapter.** The quest pays. A second payer is how one rule
  ends up implemented twice and answered slightly differently, which is the defect this repo
  keeps re-filing.
- **Do not write a fact from story code.** Story reads. If a chapter must make something true,
  that is a quest step or an event beat.
- **Do not add a fourth `kind` to `QuestDef` or a kind-specific field.** The whole design is
  that three kinds share one shape; `test_quest_content.gd` asserts it against shipped content.
- **Do not treat an unmet gate as an error to fix.** Hiding content *is* the feature: it is what
  lets the main story coexist with the sandbox. A gate that blocks play would be a bug.
- **Do not invent a gate verb.** Add it to the owning module's gate and its `KNOWN_VERBS`, or
  use a composite of verbs that exist.

---

## File map

| Path | What it is |
|---|---|
| `game/src/modules/story/story_def.gd` | story schema |
| `game/src/modules/story/story_chapter_def.gd` | chapter schema |
| `game/src/modules/story/story_gate.gd` | the requirement verbs |
| `game/src/modules/story/story_catalog.gd` | content loading |
| `game/src/modules/story/api.gd` | the only file others may reference |
| `game/data/story/stories/` | authored stories |
| `game/tests/modules/story/` | fixture + content tests |
| `game/src/modules/quest/` | `QuestDef`, `QuestStepDef`, `QuestApi` |
| `game/data/quest/quests/` | authored quests |
| `game/src/modules/event/` | `EventDef`, `EventStageDef` |
| `game/data/event/` | authored events |
| `tools/arch/families.json` | family registration (`stories`, `quests`, `events`) |
| `docs/modding-guide.md` | manifest, load order, overlay, failure modes |
