# HANDOFF — the unique-characters asset program

Written by an auditing session. Everything below is verified against the tree; each claim names
what was read. Read `WORKFLOW.md` and `ART_CRITERIA.md` first — they are good, and this file only
covers what they do not.

**This folder is a nested git checkout of a PRIVATE repo, and is gitignored here.**
`.gitignore:11` ignores `game/assets/characters/unique-characters/`, so `git ls-files` returns **0**
*from this repo* — but `unique-characters/.git/config` reads
`url = https://github.com/letuhao/chaos-world-content.git`. **The program is version-controlled,
just not where this project can see it.** Do not "fix" the ignore rule without reading this: adding
the path while `.git/` is present stages a *gitlink*, so every clone gets an empty directory.
The durable items from this handoff are mirrored into `docs/deferred.jsonl`.

---

## 1. What exists, verified

- **25 PNGs, 51.4 MB, one character: Ilsa Renn (`unique-0001`).**
- All `RGBA`, all with real alpha (`getextrema()[0] == 0`), transparency 21.7 % – 76.9 %.
  **Background removal works.** `audit_images.py`'s automated checks pass.
- `docs/PROMPT_AUDIT.md`, `docs/VALIDATION_AUDIT.md`, `docs/WORKFLOW_AUDIT.md` are real audits
  (95 KB) and their findings are correct. `WORKFLOW_AUDIT.md` rates it Design 8/10,
  **Implementation 4/10, Validation 3/10, Scalability 2/10**.

**The rendering half of this program works.** Everything after render is unwritten. That is the
whole finding.

---

## 2. The gap: rendered ≠ reachable

Three independent breaks. Any one of them alone makes the art unloadable; all three are present.

### GAP 1 — not one of the 25 files is indexed

`unique-0001`'s record in `game/assets/characters/unique-index*.jsonl` has **all 22 shots at
`status: "planned"` with `path: None`**, and `published_as` is `{"portrait_id": "", "def_path": ""}`.

So: **25 PNGs on disk, 22 of them the spec'd shot set** (7 single-shot + 9 `expression_set` +
6 `pose_set`), plus 3 unscheduled `daily_*`. **0 of the 22 indexed**, 0 synced to a `.tres`, 0
reachable by the game.
`published_as` has **no readers anywhere in `game/src`** (verified by grep). This is the exact
"assets that cannot map or link" case, with 51 MB of it.

### GAP 2 — daily-life art has no slot to live in

`PROMPT_SLOTS` (`tools/unique_characters.py:75`) is: `map_sprite`, `dialogue_portrait`,
`character_portrait`, `concept_art`, `environmental_concept`, `combat_concept`,
`relationship_scene`, `expression_set`, `pose_set`. **There is no daily slot.**

`ilsa_daily_casual.png`, `ilsa_daily_working.png` and `ilsa_daily_romance.png` therefore cannot be
canon: `SLOT_KIND` (`tools/unique_characters.py:91`) has no kind to route them to, and a shot
without a valid `slot` is refused at any status.

Meanwhile `ART_CRITERIA.md:420` has a section titled **"Daily Art Scenes Must Show Personality"**.
The criteria define a family the schema cannot hold. Note also that `daily_romance` is a
**two-character** shot, which is what `relationship_scene` already is — so a daily family needs a
decision on whether romance is a daily scene or a relationship scene, not both.

### GAP 3 — every canvas is wrong, so nothing would install

| file(s) | actual | required |
|---|---|---|
| 24 of 25 | `1248×1664` (one canvas for everything) | per-shot, declared on the shot |
| `ilsa_map_sprite.png` | `896×1184` | **`128×192`** |

The proven crowd specs are `character_assets.py:256` (`map_sprite` `canvas_px: [128, 192]`, with
`"centered with a bottom-center ground pivot"` at `:263`) and `:268` (`dialogue_portrait`
`[384, 512]`).

`_validate_image` (`tools/unique_characters.py:959`) requires an installed PNG to match its shot's
declared canvas **exactly**. One canvas for 24 shots means nothing distinguishes a map token from
a dialogue portrait except a single outlier — and that outlier is 7× the proven map size.
**All 25 would be rejected on install.**

---

## 3. Character fidelity fails across the set, and nothing gates it

**23 of the 25 renders fail, not one.** Only `expression_01` and `pose_06` are candidates for
passing. The set is homogeneous in its failure, which has two consequences that shape any gate:

- **No threshold may be calibrated by contrast within this set.** A threshold tuned to separate
  `daily_romance` from "the rest" is tuned against 22 images that are equally wrong. Thresholds
  must be anchored on the **authored** palette hexes (`ART_CRITERIA.md:32-38`) and the appearance
  prose (`README.md:36-50`), with these images used only as red-path fixtures.
- **The prompt lever is already exhausted.** `batch_generate_ilsa.py:176` already carries
  `PROMPT_AUDIT.md`'s rewritten `daily_romance` prompt — *"no romantic tension, no intimacy, no
  attraction, flat professional interaction"*. The shipped PNG still has the blush, the bob and the
  pendant. More prompt engineering was tried and did not work; that is the argument for a machine
  gate.

`ilsa_daily_romance.png` against the spec in `README.md:38-46`:

| Spec | Rendered |
|---|---|
| Age 41 | reads ~16 |
| Hair cropped short, cut with a blade | blunt bob with bangs |
| Complexion: **no flush** | heavy blush across cheeks and nose |
| Near-monochrome: ivory / ash / pale jade / dull brass | cream + teal + gold ornament |
| **No livery, no sect colour** | ornate floral embroidery |
| Stillness "trained rather than inherited" | decorative fantasy-adventurer stance |

And `README.md:45` — *"Marks: none. The absence is the most alarming thing about her in a room of
cultivators"* — the render gives her elaborate decoration, which inverts the character's one
designed trait.

`docs/PROMPT_AUDIT.md` predicted this exactly: *"will produce attractive anime girls in ~80% of
generations, with the worst offenders being `daily_romance`, `expression_04`, and `expression_09`."*
**The audit was right and is not a gate.** Nothing fails when a render contradicts its criteria, so
quality depends on a human noticing.

Defects **no audit recorded**: `pose_02` renders on an **opaque** ivory ground — invisible to
`_validate_image`, which asserts only `getextrema()[0] == 0`, a test **one** transparent pixel
passes. `environmental_concept` holds three figures; `pose_01` holds five. Five images have baked
text. `pose_02` has dark marks on the cheek and hands against `README.md:45` *"Marks: None"*.

**`scripts/validate.py` cannot fail and is calibrated backwards.** Its docstring (`:4-14`) announces
V1–V9; only V1, V2, V3, V8, V9 exist — V4 (attractiveness), V5/V6 (diversity), V7 (culture) are
announced and never written (`validate_all` `:155-161` calls five). `main()` returns `None`
(`:195`), so the process exits **0** with failures present; `import sys` at `:18` is unused.
**`:39` declares `map_sprite` should be `(896, 1184)` — so it PASSES the one image the game would
REJECT**, because the proven spec is `128×192`. Its thresholds were reverse-engineered *from* the
bad renders. `audit_images.py` has the same defect (`audit()` `:39` returns issues, the guard `:42`
discards them) and disagrees with `validate.py` on the same threshold — **10 %** at `:28` versus
**20 %** at `:80`.

**`docs/VALIDATION_AUDIT.md:630-687` prints a fabricated report** — `mean_sat=0.12`,
`palette_match=82%`, `risk_score=0.31`, `lap_var=187` — presented as measured. Nothing was
measured. Its thresholds are also unsourced and provably wrong against the shipped art: `:465`
("vertical, >10° FAIL") would refuse `pose_05` and `relationship_scene`, which are seated *by their
own criteria*, and `:380` (`skin_pct > 25% FAIL`) has no kind-aware ceiling, so it would refuse a
close head-and-shoulders portrait. **Keep its §3 hex table; discard §4 and §10.**

---

## 4. Work items, in order

Each states the guard that makes it verifiable. A green check that discriminates nothing is worse
than a red one (INC-0016) — every item below needs a case that goes RED when the guard is removed.

### W1 — index the art that already exists *(highest value; nothing else matters until this lands)*
- Give each of the 22 shots its real `path`, `status`, and provenance (`source`, `prompt`,
  `generated_on`, `license`) so `_validate_image` can run.
- **Requires W3 first** — a path is refused unless the file matches the shot's declared `canvas`.
- Guard: `unique_characters check` passes with `check_files=True`, i.e. `audit` is green over real
  files rather than over `planned` rows.

### W2 — a `daily` family with a real slot
- Add a slot and a kind so daily shots are placeable, and a canon minimum that is counted on
  **distinct daypart text** — not a shot count. Four shots all reading `dusk` must fail, exactly as
  nine identical expressions fail today.
- The daypart vocabulary must carry **no duration and no period count**. `_no_stat_numbers`
  (`tools/unique_characters.py`, ADR 0138) exists because a number in a reference document is a
  balance surface no gate can see. There is no day/season/year concept in the game today, and
  `core/time_ladder.gd` — the named home for time ratios (ADR 0173) — **is not written**.
- Guard: a red-path case proving four identical dayparts fail and four distinct ones pass.

### W3 — per-shot canvas discipline
- Declare `canvas` per shot from the proven specs: `map_sprite` 128×192 bottom-center pivot,
  `dialogue_portrait` 384×512. Re-render `ilsa_map_sprite` at 128×192 or it stays uninstallable.
- A per-character free canvas is fine (ADR 0138) — **one canvas for 24 different slots is not**,
  because it is what makes a map token indistinguishable from a portrait.
- Guard: `_validate_image` rejects a mismatched canvas, proven by a case that installs a
  deliberately wrong size and sees it refused.

### W4 — a fidelity gate, so an audit is a gate
- Turn `PROMPT_AUDIT.md`'s finding into something that fails: at minimum, check the rendered
  palette against the approved hex set and flag an image whose visible palette is far from it.
  Cheapest honest version: record the approved palette per shot in the criteria and assert the
  render's dominant colours are within it.
- Guard: the existing romance image must FAIL this gate. A gate the current bad art passes is not
  a gate.

### W5 — repository hygiene
- **This folder is a private nested repo, not untracked scratch** — see the header. `git ls-files`
  returning 0 is a *visibility* fact, not a *versioning* fact. Do not narrow `.gitignore:11` while
  `.git/` is present.
- `README.md:70` and `WORKFLOW.md:261` invoke `python scripts/generate.py` directly. AGENTS.md
  requires `uv run python -m tools <task>` and says *"Do not rely on bare `python`."* Every
  automation entrypoint is a Python module run through `uv`.
- **Models, workflows and LoRAs live in a separate `local-image-generator-service` repo**, and
  `generate.py:38` hardcodes `G:\Works\local-image-generator-service`. **The workflow graph itself
  IS in this repo**, as a Python dict at `tools/map_generate.py:220` (`KREA2_ITEM_WORKFLOW`), so the
  second implementation is unnecessary — but the two are **not interchangeable**:
  `KREA2_ITEM_WORKFLOW` has no `PreviewImage` node and no `ResolutionSelector`, both of which
  `generate.py:220,235` require, while `character_assets.py:974-981` *adds* the selector as node
  `"857"` and hardcodes every other id. `generate.py` is robust to graph shape but needs a file
  that is not here; `character_assets` is self-contained but brittle to id changes.
- `scripts/__pycache__/generate.cpython-313.pyc` is a build artifact.
- `WORKFLOW.md:244` documents `batch_generate.py`; the real file is `batch_generate_ilsa.py`. There
  is **no second phantom**: `validate.py` **does** exist (167 lines) and `--only-failed` **is**
  implemented (`batch_generate_ilsa.py:199`) — two earlier claims that they were missing were wrong.
  A third phantom nobody documented: `generate.py:214` names `workflows/krea2_turbo.json`, which is
  neither the configured `WORKFLOW` (`:40`) nor anything real.
- Decide one way: commit the scripts and criteria with the PNGs ignored, or move the program under
  `tools/` as a task. Half-in is what produced the current state.

### W6 — dual-cultivation art is a scope decision, not a gap to fill
There is **no dual-cultivation art** and no slot for it. `modules/dual_cultivation` exposes
`attach` and `succubus_path` only — **no verbs at all** (`api.gd:14,20`; `CHARM`/`FERTILITY`/
`POTENCY` at `:9-11` are stat ids, not actions). So there is nothing for art to depict yet.
If it is ever made, AGENTS.md is binding: dual-cultivation is a **clinical gameplay mechanic** —
a cultivation-path concept plate, or two participants and a labelled qi-exchange diagram. Nothing
sexual, suggestive or explicit. Same rule as the succubus and fertility mechanics.

**Ask the user before starting W6.** It is a content decision, not an obvious omission.

### W7 — content safety: the generation path can post an unconstrained prompt *(highest severity)*

AGENTS.md: *"succubus, dual-cultivation, and fertility are pure gameplay mechanics — never write
sexual, explicit, or suggestive prose, descriptions, names, or assets."* Three measured problems on
the path that produced the 25 shipped renders:

1. **`scripts/generate.py` has NO negative-prompt path at all.** `:219` writes the prompt into the
   **first** `CLIPTextEncode` it finds and never sets a second one. Run it directly and ComfyUI
   receives **zero negative conditioning** — every suppressor in `CHARACTER_NEGATIVE`
   (`tools/character_assets.py:292-301`, which names `sexualized pose, erotic framing, fetish
   clothing, explicit sexual content, nudity, … sexualized minor`) is absent.
2. **`batch_generate_ilsa.py:51-67` omits that whole category.** It suppresses beauty, anime, youth
   and glamour, but not `nudity`/`erotic framing`/`sexualized`. Its only protection is
   `BRIEF_CONSTRAINTS` (`tools/unique_characters.py:159-166`), which is **positive-side text**, not
   negative conditioning — and it reaches only the `_brief` path, never `generate.py`.
3. **The checkpoint is the uncensored variant.** `tools/map_generate.py:21`
   `KREA2_MODEL = "krea2/raySemiReal_krea2TurboV1Nsfw.safetensors"`, echoed at `WORKFLOW.md:319`.
   Every render went through it with, per (1) and (2), no explicit-content suppression.

**Age ambiguity is live and unguarded.** The audited render reads ~16 against a spec of 41, and
`batch_generate_ilsa.py:30` opens with weighted `(plain:1.4) (unremarkable:1.3) (forgettable:1.3)`
while `:55` merely negates `young, youthful, teenage, child` — a bare "not young" is a weak age
anchor. `expression_09` (`:146`) additionally negates `no defiance, no strength, no determination`,
stripping the cues that read as adult.

What genuinely cannot be automated, stated plainly so nobody pretends otherwise: **apparent age,
hair crop, pose/bearing, garment coverage, and any sexualized reading of the image.** With Pillow
and no CV model there is no reliable pixel proxy for any of them. The machine should enforce
*bounds* (single figure, off-palette saturation, skin flush, brass area, background transparency);
a human performs *review*, and only a human sets `approved`. Keep that checklist as a **Python
constant beside the gate**, not as Markdown — AGENTS.md forbids new Markdown without asking, and a
doc next to nothing drifts from the code it governs.

**The strongest existing guard is structural and should not be rebuilt:** `PROMPT_SLOTS`
(`tools/unique_characters.py:75`) and `SLOT_KIND` (`:91`) have **no slot and no kind for
succubus/dual-cultivation/fertility art**, and a shot without a valid `slot` is refused at any
status — so such an asset cannot be indexed even if it were rendered.

---

## 5. Do not

- **Do not add a `core/unique_index.gd` reader.** ADR 0138 states the game never reads the
  catalog. The sanctioned bridge is index-row → an authored `.tres` under `res://data/portraits/`,
  read by the existing `PortraitCatalog`. ADR 0138 itself promises this via `published_as`.
- **Do not relax the canon gate to admit daily art.** ADR 0153's argument is that a gate that
  passes while saying the same thing twice "looks complete" — the tier may reduce what gets
  *rendered*, never what must be *authored* (ADR 0176).
- **Do not commit the 51 MB of PNGs.** Index them; the art stays local.
- **Do not trust `report` for identity.** `unique-characters.py:120` `DEFAULT_CANVAS` is dead code,
  and `tools/check.py` cites ADR 0139 for the Lore Bible when it is ADR 0144.

---

## 6. Decided already — do not re-litigate

Four ADRs cover this program and are committed:

| ADR | Decides |
|---|---|
| **0175** | assets are a second index keyed by shot (`unique-assets.jsonl`, **never** `unique-index-*` — the character glob would read it); `family` is derived from `slot`; `reuse` may only name ids that already exist; the game reads authored resources only |
| **0176** | a bundle tier comes from `identity.role` and gates **rendering, never authoring** |
| **0177** | a portrait variant is chosen by a key the game already publishes, and `layer_paths` composes back to front — today `portrait_panel.gd:146-154` loads the first layer and returns, so a bundle renders as one image |
| **0178** | a daypart is a closed presentation vocabulary carrying **no duration**; its ratio is owed to ADR 0173's `TimeLadder`, which does not exist yet |

Two defects already fixed in the same area, so do not re-investigate them:
- `PortraitIndex.portrait_path` / `validate` filtered `status == "generated"` while
  `character_assets install` writes `approved` — 18 shipped portraits resolved to the placeholder
  while the catalog reported them as art. Fixed; one `INSTALLED_STATUSES` constant now serves both.
- `[] as Array[StringName]` yielded an untyped array on the first row of every race in
  `portrait_index.gd`. Fixed.

---

## 7. Verified references

```
tools/character_assets.py:256       map_sprite canvas_px [128, 192]   <- the proven map spec
tools/character_assets.py:263       "centered with a bottom-center ground pivot"
tools/character_assets.py:268       dialogue_portrait canvas_px [384, 512]
tools/unique_characters.py:73       SHOT_KINDS
tools/unique_characters.py:75       PROMPT_SLOTS          <- no daily slot
tools/unique_characters.py:91       SLOT_KIND             <- where a daily shot would be refused
tools/unique_characters.py:635      _validate
tools/unique_characters.py:959      _validate_image       <- exact-canvas rule
tools/unique_characters.py:1737     _install
game/src/ui/panels/portrait_panel.gd:146-154   loads the FIRST layer and returns
tools/arch/rules.py:163             MAX_FACADE_PUBLIC_METHODS = 12
```

`NpcApi` is **at 12/12** — a thirteenth public method is a hard `tools arch` failure. `combat`
has 3 free slots, `combat_engine` has 1.

**Claim before you edit.** `uv run python -m tools claim_guard claim --session <id> --paths <p>`
(repeated `--paths` accumulates, INC-0037). Eight sessions are writing
`game/assets/characters/unique-index-wave-*.jsonl` right now, and `tools/unique_characters.py` is
being edited concurrently. Any schema change must be **additive**; do not restructure existing
character records in place.
