# 0193 Rendered character art is gated per image on its authored palette, and a threshold is only ever tightened

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0175 (assets are a second index keyed by shot; the game reads authored resources only), ADR 0176 (a tier gates rendering, never authoring), ADR 0138 (the named cast is reference data)
- Implements: DEF-0256. Refines: DEF-0255.

## Context

`game/assets/characters/unique-characters/` holds 25 finished renders for one character and three
audits claiming to validate them. Two measurements make those audits worthless:

- **They cannot fail.** `audit_images.py:39` returns its issues and the `__main__` guard at `:42`
  discards them; `validate.py`'s `main()` returns `None` (`:195`). Both exit 0 with failures
  present, so nothing in the program can be red.
- **One of them is calibrated backwards.** `validate.py:39` declares `map_sprite` should be
  `(896, 1184)` — which is the single shipped image the **game** would reject, because the proven
  spec is 128×192 (`tools/character_assets.py:256`). It passes the art that matters and would fail
  correct art. That is INC-0016 exactly: a green gate that discriminates nothing.

Meanwhile `PROMPT_AUDIT.md` predicted the failure class — "attractive anime girls in ~80% of
generations", naming the worst shots — and **23 of 25 renders fail it**. Worse, the prompt lever is
already exhausted: `batch_generate_ilsa.py:176` carries the audit's rewritten `daily_romance` prompt
("no romantic tension, no intimacy, flat professional interaction") and the shipped PNG still has
the blush, the bob and the pendant.

## Decision

**The gate is per image, anchored on authored data, and a threshold may only ever be tightened.**

- **`tools/art_fidelity.py` gates four things and only four:** figure count against
  `BRIEF_CONSTRAINTS` "One subject only"; background transparency; dominant-colour containment in
  the authored palette; and a per-kind ceiling on skin area. It is invoked **per image** at
  install/approve time, **never added to `tools check`** — 13 of 25 renders fail, so a build-level
  gate would be permanently red, and a permanently-red command stops being read.
- **Thresholds are authored, derived, or frozen against a human-confirmed render. Never derived
  from the failing art.** The shipped set is homogeneous in its failure, so a threshold tuned to
  separate the worst image from "the rest" is tuned against 22 images that are equally wrong. The
  distance limit and the off-palette budget were calibrated once against the two renders a human
  confirmed clean and then frozen. **Calibrating on the known-good is not circular; calibrating on
  the known-bad is.** Thereafter a threshold may only be tightened — the `core/realm_power_table.tres`
  discipline (AGENTS.md:141). The command says so in its own failure message.
- **The authored palette is duplicated into the tool as a tracked constant, deliberately.** Its
  source (`ART_CRITERIA.md:32-38`) lives in a gitignored private checkout, so a threshold recorded
  only there is recorded where no CI run and no reviewer can read it. A selftest asserts the
  authored palette **passes its own gate**: had the reference colours failed, the limit would have
  come from the art rather than the criteria.
- **What is not automatable is named, measured, and refused rather than shipped.** Skin flush,
  ornament area, hair crop, apparent age, pose/bearing, garment coverage and sexualised reading were
  each implemented and measured against the 25 renders, and each **failed to track the visual
  verdict** — the flush metric scores the cleanest render highest, and a hue window wide enough to
  cover a warm palette matches 36–73% of *every* frame. They moved to a manual checklist, printed by
  `art_fidelity review`, which a human works through before `approved` is set. The checklist is a
  Python constant beside the gate, not Markdown: AGENTS.md forbids new Markdown without asking, and
  a checklist kept beside the gate it gates cannot drift from it.
- **The content rule is enforced structurally, not by this gate.** AGENTS.md requires succubus,
  dual-cultivation and fertility art to stay clinical. `SHOT_KINDS` and `SLOT_KIND`
  (`tools/unique_characters.py:73,91`) have **no slot or kind** for such art and a shot without a
  valid slot is refused at any status, so such an asset cannot be indexed even if it were rendered.
  That guard already exists and is not rebuilt here.

## Consequences

- **A gate that can fail now exists, and the known-bad render fails it.** `ilsa_daily_romance.png`
  measures 3.5% of its frame dominated by colours far from every authored hex, against a 1% budget;
  the two human-confirmed-clean renders measure 0.0% and pass. That is the discrimination
  `validate.py` inverted.
- **13 of 25 renders are red, and that is the finding, not a bug to be tuned away.** Fixing it means
  re-rendering or relaxing the authored criteria — and relaxing the criteria is a content decision,
  not a tooling one.
- **`check` and `report` are separate commands on purpose.** `check` exits non-zero; `report` always
  exits 0 unless `--fail-on` promotes it. A permanently-red command is how a gate stops being read.
- **An absent private art folder is tolerated, not an error** — it returns `[]` and the command
  reports and exits 0, the same shape as `_lore_entries()` returning `None` to disable a rule
  rather than guessing (`tools/unique_characters.py:943-957`).
- **This gate cannot police age, and nothing should pretend it can.** The human checklist is the
  control for the traits the spec cares most about, which means `approved` remains a human decision.
  That is the honest boundary, stated here so a future agent does not read a green gate as cover.
- **Owed, not decided here:** wiring `image_findings` into `unique_characters install` and
  `character_assets approve`; re-rendering the 13 failures; and moving the private program under
  `tools/` so the duplicated ComfyUI path can be deleted (DEF-0255, which needs a user decision
  because option (a) requires deleting a nested `.git/`).
