# Workflow Audit — Unique Character Asset Generation

> **Audit date**: 2026-10-04
> **Scope**: WORKFLOW.md, ART_CRITERIA.md, context/unique-0001-ilsa-renn.md, scripts/generate.py, scripts/batch_generate_ilsa.py
> **Auditor**: Game production pipeline expert

---

## Executive Summary

The workflow is **well-conceived and philosophically sound** — the Context → Criteria → Prompt → Generate → Validate → Re-generate loop is the correct architecture. The art criteria for Ilsa Renn are exceptionally detailed and demonstrate strong prompt engineering awareness (attractiveness suppression, conceptual descriptions, diversity by design).

However, the workflow has **significant implementation gaps**: the scripts don't fully implement what the workflow describes, several referenced files don't exist, the validation layer is mostly aspirational, and the sub-program model isn't actually implemented in code. The workflow is a strong **design document** but a weak **operational specification**.

**Overall maturity**: Design 8/10, Implementation 4/10, Validation 3/10, Scalability 2/10.

---

## Prioritized Issues

### P0 — Critical (Blocks correct operation)

#### 1. Referenced files don't exist

| Reference | Actual Status |
|-----------|---------------|
| `WORKFLOW.md:245` — `scripts/batch_generate.py` | File is `batch_generate_ilsa.py` |
| `WORKFLOW.md:247` — `scripts/validate.py` | **Does not exist** |
| `WORKFLOW.md:268` — `--only-failed` flag | **Not implemented** in `batch_generate_ilsa.py` |

**Fix**: Create `scripts/validate.py` (even a stub that reports "not yet implemented"), add `--only-failed` to the batch script, and correct the file structure listing in WORKFLOW.md.

#### 2. Daily art shots have no criteria

`batch_generate_ilsa.py:159-182` defines 3 daily art shots (romance, working, casual) that are **completely absent from ART_CRITERIA.md**. The criteria document only covers 22 shots; the batch script generates 25.

**Fix**: Either add shots 23-25 to ART_CRITERIA.md with full criteria, or remove them from the batch script. The workflow's own rule — "never write a prompt without per-shot criteria" — is violated.

#### 3. Batch script comment is outdated

`batch_generate_ilsa.py:3` says "nine-prompt visual set" but the script generates 25 shots. This is a v2→v3 leftover that will confuse agents.

**Fix**: Update docstring to "25-shot visual set (22 core + 3 daily art)".

#### 4. No `--only-failed` implementation

`WORKFLOW.md:268` documents `python scripts/batch_generate.py --character-id unique-0001 --only-failed` but the batch script has no such flag. The re-generation loop (Phase 6) is not actually supported by the tooling.

**Fix**: Add `--only-failed` flag that reads a validation report and only regenerates failed shots. Or remove the flag from the workflow documentation.

---

### P1 — High (Significant quality/consistency risk)

#### 5. Expression shots share identical framing — diversity contradiction

`ART_CRITERIA.md:164-286` — All 9 expression shots specify "close head and shoulders" as the composition. But `ART_CRITERIA.md:379` states: "no two shots share the same framing." This is a direct contradiction.

**Fix**: Either:
- (a) Vary framing for expression shots (e.g., expression-01 waist-up, expression-02 close-up, expression-03 three-quarter), or
- (b) Add an exception to the diversity rules: "Expression shots may share framing; diversity is achieved through face/body/light."

#### 6. Pose shots share identical framing

`ART_CRITERIA.md:290-370` — All 6 pose shots are "full figure." Same contradiction as above.

**Fix**: Same as #5. Vary framing or add explicit exception.

#### 7. No character consistency enforcement across shots

The workflow designates Shot 3 (`character-portrait`) as "the reference image all other shots must match" (`ART_CRITERIA.md:98`), but there is **no process or tooling** to enforce this. Nothing compares Shot 1 (map sprite) or Shot 17 (doorway stillness) against Shot 3.

**Fix**: Add a consistency check step — either automated (embedding similarity via CLIP) or manual (agent compares against reference). Document the process in Phase 5.

#### 8. No palette validation

`ART_CRITERIA.md:28-38` defines exact hex codes, but no validation checks whether generated images actually use those colors. The automated checks (`WORKFLOW.md:134-139`) only verify alpha, transparency, and dimensions.

**Fix**: Add a palette check to `audit_images.py` — sample pixels and verify they fall within tolerance of the approved hex codes.

#### 9. No map sprite readability check

`ART_CRITERIA.md:70` requires the map sprite to be "identifiable at 256×256" but there's no validation for this. A sprite can pass alpha/dimension checks and still be unreadable.

**Fix**: Add a manual validation step: "View at 256×256 and confirm silhouette is readable." Or add an automated check: downscale to 256×256 and measure silhouette contrast.

#### 10. No LoRA usage in batch script

`batch_generate_ilsa.py:205` passes `loras=[]` — no style/expression/pose LoRAs are used. The workflow's `generate.py` supports LoRA slots and the workflow mentions them, but the batch script doesn't use them. This means all style control comes from prompt text alone.

**Fix**: Either:
- (a) Add LoRA support to the batch script (at minimum a style LoRA for `cultivation-fantasy-relic`), or
- (b) Document that LoRAs are intentionally unused for this character and explain why.

#### 11. Hardcoded paths in generate.py

`generate.py:35` hardcodes `G:\Works\local-image-generator-service`. This breaks on any other machine or if the repo moves.

**Fix**: Use an environment variable or config file:
```python
_GEN_SERVICE = Path(os.environ.get("CHAOS_WORLD_GEN_SERVICE", r"G:\Works\local-image-generator-service"))
```

#### 12. No seed reproducibility verification

The workflow sets deterministic seeds (`batch_generate_ilsa.py:55,63,71...`) but never verifies that the same seed produces the same output. ComfyUI workflows can be non-deterministic due to GPU state, model loading order, or workflow variations.

**Fix**: Add a reproducibility check — generate the same shot twice with the same seed and compare hashes. Document the expected behavior.

---

### P2 — Medium (Completeness gaps)

#### 13. Missing lore domains in context collection

`WORKFLOW.md:23` lists `lore/edges/*.jsonl` as an input but the process (lines 27-34) never resolves it. The context summary (`unique-0001-ilsa-renn.md`) has no relationship data.

**Missing domains**:
- **Relationships**: Who are Ilsa's relationships? What conflicts define her? (Critical for `relationship-scene` shot)
- **History/Timeline**: What events shaped her? The "40 years being the world's baseline" is mentioned but no specific events.
- **Other characters**: How does she relate to other unique characters? Needed for multi-character shots.
- **Motivations/Goals**: Why does she refuse residence? What does she want?
- **Fears**: What threatens her? The "unwarnable" trait is mentioned but not explored.
- **Items/Equipment**: The "standard weight in her pocket" is mentioned but not detailed.

**Fix**: Add a step in Phase 1 to resolve `lore/edges/*.jsonl` and include relationship data in the context summary template.

#### 14. No export/delivery phase

The workflow ends at "all shots pass validation" but never describes how assets get into the game. Missing:
- Final naming convention for deliverables
- Metadata sidecar files (JSON with seed, prompt, criteria version)
- Integration step (copy to game assets directory)
- Version control for generated assets

**Fix**: Add "Phase 7: Export & Integration" describing the delivery format and process.

#### 15. No time/resource estimation

The workflow doesn't estimate how long generation takes or what resources are needed. With 25 shots at ~30-60s each plus 2s delays, this is 15-30 minutes per character. For a game with many unique characters, this matters.

**Fix**: Add a "Resource Planning" section with per-shot time estimates and total time budget.

#### 16. No error recovery beyond re-generation

Phase 6 covers re-generation for quality failures but not for:
- ComfyUI unavailable/offline
- Model produces consistently bad output (systematic failure)
- GPU out-of-memory
- Disk full

**Fix**: Add an "Error Recovery" subsection in Phase 6 with fallback strategies.

#### 17. No maximum retry count

`WORKFLOW.md:176` says "Repeat until all shots pass" — this could loop forever. There's no maximum attempt count or escalation path.

**Fix**: Define max retries (e.g., 3 attempts per shot) and an escalation path (e.g., "after 3 failures, flag for manual review").

#### 18. No seed variation strategy

`WORKFLOW.md:174` says "Regenerate with a new seed" but doesn't specify how the new seed is chosen. Random seeds make debugging harder; incremental seeds are more reproducible.

**Fix**: Define a seed strategy: "new seed = original seed + attempt_number * 1000" or similar.

#### 19. No prompt version tracking

When prompts are modified during re-generation, there's no way to track which prompt version produced which result. This makes it impossible to reproduce or debug.

**Fix**: Add a `prompt_version` field to the generation log and output metadata.

#### 20. Inconsistent formatting in ART_CRITERIA.md

`ART_CRITERIA.md:342,356,370` — The negative prompt field is quoted with backticks (`` `negative prompt` ``) instead of bold (`**Negative prompt**`) like all other shots. This is a minor inconsistency but suggests these shots were added later without following the template.

**Fix**: Change `` `negative prompt` `` to `**Negative prompt**` for consistency.

---

### P3 — Low (Polish and best practices)

#### 21. No prompt length management

The universal positive prompt (`batch_generate_ilsa.py:21-32`) is ~80 tokens. For expression shots, the full prompt becomes 80 + ~30 = ~110 tokens. This is within limits but the important shot-specific details are at the end, where they have less influence.

**Fix**: Consider restructuring prompts to put shot-specific details first, universal elements last. Or use attention weighting for critical terms.

#### 22. No attention weighting

The workflow doesn't mention using attention weighting (e.g., `(keyword:1.2)`) which is standard in Stable Diffusion prompt engineering for emphasizing/de-emphasizing elements.

**Fix**: Add a note in Phase 3 about when to use attention weighting (e.g., `(plain:1.3)` for attractiveness suppression).

#### 23. No CLIP skip consideration

For Krea2 Turbo, CLIP skip is important for style control. The workflow doesn't mention it.

**Fix**: Add a note in Phase 3 or Phase 4 about CLIP skip settings for the Krea2 workflow.

#### 24. No CFG/sampler/scheduler documentation

These are critical generation parameters. The workflow uses Krea2 Turbo which has specific requirements (CFG 1.0, euler, simple scheduler per the repo's AGENTS.md).

**Fix**: Add a "Generation Parameters" section documenting the required settings for the Krea2 workflow.

#### 25. No parallel generation option

The batch script generates sequentially with 2s delays. For 25 shots, this is slow. No mention of parallel options (e.g., multiple ComfyUI instances).

**Fix**: Document whether parallel generation is supported and under what conditions.

#### 26. No timeout handling in batch script

If one shot hangs (ComfyUI unresponsive), the entire batch hangs indefinitely. `generate.py:251` has a 30-min timeout but the batch script doesn't handle it gracefully.

**Fix**: Add per-shot timeout handling with retry logic in the batch script.

#### 27. Sub-program model not implemented in code

The workflow says "each asset is a sub-program" (`WORKFLOW.md:195`) but the implementation is a single hardcoded script (`batch_generate_ilsa.py`). There's no generic batch runner that works for any character.

**Fix**: Either:
- (a) Refactor `batch_generate_ilsa.py` into a generic `batch_generate.py` that reads criteria from a YAML/JSON file, or
- (b) Document that each character gets its own hardcoded batch script (current approach) and explain the trade-offs.

#### 28. No per-asset spec files

The sub-program template is defined (`WORKFLOW.md:198-232`) but no actual per-asset spec files exist. Everything is in the monolithic ART_CRITERIA.md and batch script.

**Fix**: Create per-asset spec files (e.g., `specs/ilsa-renn.md`) that follow the template, or document that ART_CRITERIA.md + batch script entries serve as the spec.

#### 29. No validation report format

`WORKFLOW.md:162` says "Validation report with pass/fail per shot" but doesn't define the format. Is it JSON? Markdown? CSV?

**Fix**: Define the validation report format (suggest JSON for machine-readable + Markdown for human-readable).

#### 30. No "good enough" criteria

The workflow says "re-generate until pass" but doesn't define what "pass" means for subjective criteria like "quality" or "character fidelity." This leads to infinite loops or arbitrary acceptance.

**Fix**: Define "good enough" thresholds for subjective criteria (e.g., "character fidelity: agent confidence > 70%").

---

## Detailed Analysis by Phase

### Phase 1: Context Collection

**Strengths**:
- Clear input/output specification
- Good use of lore references
- Context summary template is well-structured

**Gaps**:
- `lore/edges/*.jsonl` listed as input but never resolved
- No relationship data in context summary
- No motivation/goal/fear data
- No item/equipment details
- No process for handling missing lore (what if a reference doesn't exist?)

### Phase 2: Art Criteria Generation

**Strengths**:
- Per-shot criteria with distinguishing features
- "What to render" vs "What to suppress" table is excellent
- Specific hex codes for palette
- Diversity rules are well-defined
- Silhouette keywords are a nice touch

**Gaps**:
- Criteria read like final prompts, not criteria (line between Phase 2 and Phase 3 is blurred)
- No technical quality criteria (resolution, DPI, file format)
- No cross-shot consistency criteria
- Expression and pose shots share framing (contradicts diversity rules)
- Daily art shots missing from criteria document

### Phase 3: Prompt Engineering

**Strengths**:
- Strong attractiveness suppression techniques
- Conceptual descriptions over literal ones
- Clear positive/negative separation
- Good use of "absence" as a technique

**Gaps**:
- No prompt length management
- No attention weighting
- No CLIP skip consideration
- No CFG/sampler/scheduler documentation
- Prompt structure is flat (no grouping)
- No prompt order strategy

### Phase 4: Generation

**Strengths**:
- Deterministic seeds
- Background removal via RMBG
- 2s delay between generations
- Logging of results

**Gaps**:
- No LoRA usage
- No parallel generation
- No timeout handling
- No seed reproducibility verification
- Hardcoded paths
- No error recovery for infrastructure failures

### Phase 5: Validation

**Strengths**:
- Automated + visual inspection combination
- Clear pass/fail criteria table
- Good coverage of technical checks

**Gaps**:
- `validate.py` doesn't exist
- No character fidelity automation
- No cross-shot consistency check
- No palette validation
- No map sprite readability check
- No quality metrics (subjective criteria undefined)
- No validation report format

### Phase 6: Re-generation Loop

**Strengths**:
- Failure trigger table is comprehensive
- Clear mapping from failure to fix

**Gaps**:
- No maximum retry count
- No escalation path
- No seed variation strategy
- No `--only-failed` implementation
- No prompt version tracking
- No "give up" criteria
- No infrastructure failure handling

### Sub-Program Model

**Strengths**:
- Clear template defined
- Philosophy is sound (each asset independent)

**Gaps**:
- Not implemented in code (hardcoded batch script)
- No per-asset spec files
- No generic batch runner
- No scalability path for multiple characters

---

## Recommended Fix Order

1. **Create `scripts/validate.py`** (even a stub) — P0
2. **Add daily art shots to ART_CRITERIA.md** or remove from batch script — P0
3. **Add `--only-failed` to batch script** — P0
4. **Fix file structure references in WORKFLOW.md** — P0
5. **Resolve framing diversity contradiction** — P1
6. **Add character consistency check process** — P1
7. **Add palette validation to audit_images.py** — P1
8. **Add LoRA support to batch script** — P1
9. **Fix hardcoded paths in generate.py** — P1
10. **Add lore/edges resolution to Phase 1** — P2
11. **Add export/integration phase** — P2
12. **Add max retry count and escalation path** — P2
13. **Refactor batch script to be character-agnostic** — P3
14. **Add prompt version tracking** — P3
15. **Document generation parameters (CFG, sampler, CLIP skip)** — P3

---

## Conclusion

The workflow is a **strong design document** that demonstrates sophisticated understanding of AI image generation challenges — particularly attractiveness suppression, cultural grounding, and diversity by design. The art criteria for Ilsa Renn are production-quality.

The gap is in **implementation and operational rigor**. The scripts don't fully implement the workflow, validation is mostly aspirational, and the sub-program model exists only in philosophy. The workflow needs to be treated as a **living document** that evolves with the tooling, and the tooling needs to be brought up to the workflow's ambitions.

**Recommended next steps**:
1. Fix P0 issues (1-4) — these are blocking
2. Implement `validate.py` with at least the automated checks from Phase 5
3. Add `--only-failed` to enable the re-generation loop
4. Refactor batch script to read from a criteria file (enables multi-character support)
5. Add a consistency check process (manual or automated)

---

*Audit completed 2026-10-04*
