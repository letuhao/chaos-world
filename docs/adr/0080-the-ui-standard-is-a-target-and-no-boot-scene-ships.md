# 0080 The UI standard is a target, and no boot scene ships

- Status: Accepted
- Date: 2026-10-03
- Supersedes: ADR 0038 (ui screen contract and single theme)
- Corrects: ADR 0028's "`scenes/Main.tscn` boots one body cultivator" line, and ADR 0030's
  "the pre-existing `src/app/*_cultivation_ui.gd` panels ... are removed"
- Consistent with: DEF-0035, DEF-0036, DEF-0068, BL-0095

## Context

ADR 0038 is a migration ADR: it names four defects and states what the finished state is. Read as
a description of the current UI, **four** of its claims are false — and one of them got *worse*
while the ADR was being written. A fifth is only half true.

**False claims, with evidence**

- **"`cultivation_theme.tres` is deleted" (ADR 0038:18).** It still exists at
  `game/src/ui/theme/cultivation_theme.tres`, beside `chaos_world_theme.tres`. The accurate part:
  **nothing references it** — zero occurrences of `cultivation_theme` in any `.gd` or `.tscn`. So
  the defect ADR 0038 set out to fix (a disabled button that looks enabled) is fixed; the file is
  orphaned, not removed.
- **"No `@onready` in `ui/`" (ADR 0038:20).** ADR 0038 counted 14 uses as the defect.
  `game/src/ui/` now has **16**. The count went up.
- **"`main.gd`/`mind_cultivation_ui.gd` are outside the standard and are removed, not migrated"
  (ADR 0038:29).** `game/src/app/mind_cultivation_ui.gd` exists and is still loaded by
  `game/scenes/MindCultivationUi.tscn:3`. (`main.gd` is genuinely gone.)
- **ADR 0028's "`ActorFactory.with_body_cultivation` is the composition root; `scenes/Main.tscn`
  boots one body cultivator and mounts `BodyCultivationPanel`"**. There is no `Main.tscn` —
  `game/scenes/` holds `MindCultivationUi.tscn`, `item_workbench/`, `nav/`, `domains/`, `worlds/`.
  The boot entry is `game/scenes/item_workbench/ItemWorkbenchApp.tscn`
  (`app/item_workbench_app.gd`). `src/ui/screens/body_cultivation_panel.gd` exists; nothing boots
  it as a main scene.

## Decision

**The screen contract holds. The migration is unfinished, and the two deletions never happened.**

- **What ADR 0038 actually got right, and what survives it:**
  - `game/src/ui/screens/ui_screen.gd` is the screen base with `setup`, `refresh`, `summary`,
    `on_screen_shown`, `on_screen_hidden`, `focus_initial`, `on_stack_input` and a lazy
    `_bind_nodes()` — the four `ScreenStack` hooks and `{}`-with-no-actor `summary()`, exactly as
    specified.
  - `game/src/ui/panels/stat_row.gd` and `action_set.gd` exist and own the `%d/%d` stat row and
    the action row.
- **"No number formatting in a screen" (ADR 0038:21) is only partly true.** The stat-row case is
  gone, but display values are still formatted in screens: `"%s (%d held)"`
  (`screens/crafting_screen.gd:233`), `"Anchor stage %d"` / `"Sea stage %d"` / `"%s x%d"`
  (`screens/mind_cultivation_screen.gd:90,91,239`), `"%s x%d"`
  (`screens/qi_cultivation_screen.gd:242`), `"%d permitted outcome(s), %d locked option(s), %d of
  %d treatments used"` (`screens/socket_forge.gd:333`), `"Danger: %d/10"`
  (`screens/world_map_screen.gd:271`). Several screens also build `%s%d`-style **node names**
  (`character_screen.gd:125`, `destiny_screen.gd:165,227`), which is layout, not formatting. The
  rule as written — a screen passes raw values and the panel owns the decimals and the widths — is
  not what ships; costs, stage labels and danger readouts are still the screen's job.
- **`body_cultivation` and `items` are still at the 12-method facade cap**
  (`tools/arch/rules.py:104 MAX_FACADE_PUBLIC_METHODS = 12`), so ADR 0038's consequence holds.
- **`@onready` in `ui/` is 16, not 0.** Any panel that still uses it cannot be driven headlessly
  before a scene tree exists. `tools ui drive` and `game/tools/ui_driver.gd` only reach screens
  that bind lazily.
- **`cultivation_theme.tres` is dead weight, not a competing theme.** Deleting it is a one-file
  cleanup; nothing depends on it, so nothing can break.
- **`mind_cultivation_ui.gd` is still the mind screen.** DEF-0035 and DEF-0036 record the mind
  screen as unbuilt and the UI programme as the blocker. Until that ADR retires it, `ui/` is not
  the only UI in the game and ADR 0030's promise that `ui/` is the whole UI program is aspirational.
- **`tools ui screens`** is the honest inventory of what the UI program can actually drive.

## Consequences

- DEF-0068 already says *"Boot scene never reaches cultivation: Main.tscn is orphaned."* It is
  stronger than that: the file is gone and the replacement boots the item workbench. ADR 0028's
  `Main.tscn` line is the last durable record of a scene that no longer exists.
- BL-0095 (*"Modules with no screen: combat, elements, fertility, dual_cultivation, socket,
  crafting"*) is the accurate census. Seven of seventeen modules have no screen, and one of them
  is `combat`, which per ADR 0077 is two dead files.
- The standard is not enforced by `tools arch` for any of these four points: `@onready` in `ui/`,
  a second `.tres` theme, an orphan panel, and a missing boot scene are all invisible to the
  checker. Only review catches them — which is why the record has to be accurate.
