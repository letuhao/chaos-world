"""Mutation probes for the body-cultivation balance guards.

`cultivation validate` asserting clean proves only that today's data happens to
satisfy the rules. It does not prove the rules can FAIL. A guard that has never
been seen red is indistinguishable from a guard that cannot fire, and the whole
class of defect here — a band that silently collapsed, a gate nobody had to meet —
is exactly what a vacuous assertion hides.

So each rule gets a mutation: a copy of the tree with one authored number broken in
the way that rule exists to catch, validated against that copy, and asserted to be
caught. The mutations are applied to a TEMPORARY COPY and the real data is never
touched; `run` restores nothing because it never changed anything.

Run it with `uv run python -m tools cultivation mutate`.
"""

from __future__ import annotations

import re
import shutil
import tempfile
from pathlib import Path

from ..common import ToolError, info, ok
from . import audit, ladder, report
from .report import REALM_DIR
from .seed import realms as ladder_realms

# realm id -> (scalar, broken value, the finding prefix that must fire)
#
# One per guard, each breaking a DIFFERENT number so a rule cannot pass by accident
# on a neighbour's mutation. The values are chosen to be reachable states of the
# data, not absurd numbers: the guards must fire on plausible edits, or they will not
# fire on the plausible edit a designer actually makes.
MUTATIONS: tuple[tuple[str, str, str, str], ...] = (
    # `chance_base` climbing above the ceiling is what the ORIGINAL degenerate band
    # was. Re-running that exact shape must fail.
    ("primordial_origin", "chance_base", "0.95", "degenerate_chance_band"),
    # A gate pinned onto the previous realm's ceiling leaves zero span, which is the
    # condition the shipped data had at every realm. qi_refining's own ceiling is 0.62.
    ("foundation", "quality_required", "0.620000", "quality_gate_no_headroom"),
    # A gate above the ceiling makes the realm unreachable.
    ("foundation", "quality_required", "0.700000", "gate_above_previous_ceiling"),
    # A gate at the quality a fresh huyệt already carries is passed without training.
    # That is what the first eight breakthroughs did (0.400-0.490 against a fresh 0.5).
    ("qi_refining", "quality_required", "0.400000", "gate_below_fresh_quality"),
    # Same rule, mid-ladder, where a huyệt newly unlocked also arrives at 0.5.
    ("spirit_sea", "quality_required", "0.500000", "gate_below_fresh_quality"),
    # The ladder grants physique for itself; a floor under that grant can never bind.
    ("great_luo", "physique_required", "10.0", "body_physique_gate_dead"),
    # A certainty ceiling retires the deviation loop.
    ("qi_refining", "chance_cap", "1.0", "guaranteed success"),
    # The duplicate-ladder defect: re-authoring a derived value is stale data, and it is
    # an INSERTION rather than a substitution because the field no longer exists.
    ("qi_refining", "+work_required", "40.0", "derived value"),
    ("qi_refining", "+acupoint_work", "10.0", "derived value"),
)


def _with_broken_scalar(seeds: Path, realm_id: str, scalar: str, value: str) -> None:
    """Break one scalar in one seed of a throwaway copy of the seed directory.

    A `+` prefix INSERTS the line instead of replacing one. That is how a field which
    no longer exists is exercised: the duplicate-ladder rule exists to catch a stale
    authored `work_required`, so the probe has to write one back.
    """
    target = seeds / f"{realm_id}.tres"
    if not target.is_file():
        raise ToolError(f"no realm seed to mutate: {target}")
    text = target.read_text(encoding="utf-8")
    if scalar.startswith("+"):
        field = scalar[1:]
        if re.search(rf"(?m)^{field} = ", text):
            raise ToolError(f"{realm_id} already declares `{field}`; the insert probe is void")
        broken, count = re.subn(
            rf"(?m)^(id = &\"{realm_id}\")$", f"\\1\n{field} = {value}", text, count=1
        )
    else:
        broken, count = re.subn(rf"(?m)^{scalar} = -?[\d.]+$", f"{scalar} = {value}", text, count=1)
    if count != 1:
        raise ToolError(f"{realm_id}: could not break `{scalar}` in the staged seed")
    target.write_text(broken, encoding="utf-8")


def _validate_against(seeds: Path | None) -> list[str]:
    """`audit.validate` reading realm seeds from `seeds`, or from the real tree.

    Only the seed directory is overridden. Every other content directory — items,
    recipes, meridians, acupoints, the qi path — is untouched by these mutations, so
    copying the whole of `game/data` would stage thousands of files to change thirty.
    The override covers `report` too, because that is the module holding the directory
    `audit` resolves seeds through.

    Nothing here writes to the repo: `audit` and `report` only read.
    """
    if seeds is None:
        return audit.validate()
    saved = (audit.REALM_DIR, report.REALM_DIR)
    audit.REALM_DIR = seeds
    report.REALM_DIR = seeds
    try:
        return audit.validate()
    finally:
        audit.REALM_DIR, report.REALM_DIR = saved


def _stage() -> Path:
    """A throwaway copy of the realm seed directory."""
    staged = Path(tempfile.mkdtemp(prefix="chaos_world_mutate_")) / "realms"
    shutil.copytree(REALM_DIR, staged)
    return staged


# --- The qi gate ladder, against a fixture of its own ------------------------
#
# NOT a copy of the shipped ladder, and that is the point. A ladder probe sourced
# from the corpus asserts a rule against the tree the rule was written from, so
# the day somebody fixes the ladder the probe declares the rule dead — which is
# how the acquisition selftest went red on correct content. The ladder here is
# four invented realms whose only claim to exist is to be breakable.
#
# The clean fixture must produce ZERO findings first (a rule that fires on
# everything is the same broken guard as one that fires on nothing), and each
# mutation then breaks exactly one number in the way its guard exists to catch.

FIXTURE_REALMS: tuple[tuple[str, str, int, str, int, int, tuple[str, ...]], ...] = (
    # id, name, tier, required_channel_state, depth, cap, channels
    ("st_one", "Fixture One", 1, "open", 0, 1, ("st_a",)),
    ("st_two", "Fixture Two", 1, "strengthened", 1, 2, ("st_a", "st_b")),
    ("st_three", "Fixture Three", 2, "strengthened", 2, 3, ("st_b",)),
    ("st_four", "Fixture Four", 2, "strengthened", 2, 4, ("st_b",)),
)
# Meridian id -> unlock tier. `st_deep` unlocks far above the fixture's top
# realm, so naming it is the only way to reach a boundary whose channel is never
# in the actor's hands.
FIXTURE_MERIDIANS: tuple[tuple[str, int], ...] = (("st_a", 0), ("st_b", 0), ("st_deep", 9))
# realm id -> (state line, depth line, cap line, channels line) as authored.
# The item roles are derived, not stored: every fixture realm owns three ids.
#
# The two sentinels below stand for the runtime PREMISES rather than for a seed to
# break, and they live in the probe table so a row dropped here cannot silently take
# its assertion with it (INC-0016). Each points `ladder` at a file that no longer
# declares what the guard reads.
PREMISE_STATE = "premise:meridian-state"
PREMISE_TIERS = "premise:meridian-defaults"
QI_GATE_PROBES: tuple[tuple[str, str, str, str], ...] = (
    # (realm id, line to replace, replacement, the finding that must fire)
    # A `realm id` that is one of the two sentinels above names a runtime PREMISE
    # to point at an empty file instead of a seed to break.
    # THE defect's own shape: one step of depth past what the realm below can
    # train. st_three's own cap is 3, so this trips the BOUNDARY rule alone and
    # not the own-cap one — the two are separate guards for separate causes.
    (
        "st_three",
        "required_channel_refinement = 2",
        "required_channel_refinement = 3",
        "qi_gate_demands_more_depth_than_the_realm_below_offers",
    ),
    # Depth is only ever trained on a strengthened channel.
    (
        "st_two",
        'required_channel_state = &"strengthened"',
        'required_channel_state = &"expanded"',
        "qi_gate_depth_below_strengthened",
    ),
    # A state name the runtime does not know reads as rank 0 and WEAKENS the gate.
    (
        "st_two",
        'required_channel_state = &"strengthened"',
        'required_channel_state = &"widened"',
        "qi_gate_channel_state_unknown",
    ),
    # A realm asking for more depth than its own cap. This necessarily reports
    # the boundary breach as well — the standing cap IS this realm's predecessor's
    # own cap — so the probe asserts the prefix, not exclusivity.
    (
        "st_four",
        "required_channel_refinement = 2",
        "required_channel_refinement = 7",
        "qi_gate_demands_more_depth_than_its_own_cap",
    ),
    # An unresolvable elixir: `train_channel` refuses on `has_item` before it
    # advances anything, so the whole ladder above has no verb to press.
    (
        "st_four",
        'training_item = &"st_four_channel_elixir"',
        'training_item = &"st_absent_elixir"',
        "qi_gate_item_missing",
    ),
    # A channel the actor does not hold while standing below the gate.
    (
        "st_four",
        'required_meridians = Array[StringName]([&"st_b"])',
        'required_meridians = Array[StringName]([&"st_b", &"st_deep"])',
        "qi_gate_channel_never_unlocks",
    ),
    # A gate an actor that has done nothing already passes: the body's first eight
    # breakthroughs were this, at a different number. State AND depth fall together
    # because they are independent halves of ONE gate — lowering either alone leaves
    # the other binding, which is why this is a single edit and not two probes.
    (
        "st_two",
        'required_channel_state = &"strengthened"\nrequired_channel_refinement = 1',
        'required_channel_state = &"closed"\nrequired_channel_refinement = 0',
        "qi_gate_vacuous_for_a_bare_actor",
    ),
    # A gate that checks nothing at all.
    (
        "st_three",
        'required_meridians = Array[StringName]([&"st_b"])',
        "required_meridians = Array[StringName]([])",
        "qi_gate_names_no_channel",
    ),
    # A channel no meridian definition declares.
    (
        "st_three",
        'required_meridians = Array[StringName]([&"st_b"])',
        'required_meridians = Array[StringName]([&"st_absent"])',
        "qi_gate_channel_unknown",
    ),
    # An unreadable runtime premise must be LOUD. A silent 0.0 here would leave the
    # ladder ungraded while `validate` reported clean, which is the false green
    # this whole file exists to refuse.
    (PREMISE_STATE, "", "", "gate_ladder_premise_unreadable"),
    # BL-0755: the tiers now come from `MeridianDefaults._build()`, the list
    # `unlock_for_realm` iterates. A source that no longer holds them must say so
    # rather than grade an empty ladder, which reads as "no channel is unknown".
    (PREMISE_TIERS, "", "", "gate_ladder_premise_unreadable"),
)


def _fixture_seed(row: tuple) -> str:
    """One synthetic `QiRealmSeed`, carrying only the fields the probe reads."""
    realm_id, _name, _tier, state, depth, cap, channels = row
    listed = ", ".join(f'&"{channel}"' for channel in channels)
    return "\n".join(
        [
            '[gd_resource type="Resource" script_class="QiRealmSeed" format=3]',
            "",
            "[resource]",
            f'id = &"{realm_id}"',
            f'breakthrough_item = &"{realm_id}_pill"',
            f'training_item = &"{realm_id}_channel_elixir"',
            f'recovery_item = &"{realm_id}_recovery_elixir"',
            "progress_required = 100.0",
            "comprehension_required = 10.0",
            "dantian_quality_required = 0.55",
            "dantian_fill_required = 1.0",
            f"required_meridians = Array[StringName]([{listed}])",
            f'required_channel_state = &"{state}"',
            f"required_channel_refinement = {depth}",
            f"channel_refinement_cap = {cap}",
            "",
        ]
    )


def _fixture_meridian_source(directory) -> str:
    """A throwaway `MeridianDefaults` over a throwaway corpus.

    BL-0272 made the loader READ `game/data/meridians/*.tres` through `ContentScan`,
    so a fixture of `_make` rows no longer exercises the reader at all: this stands in
    for the loader, and `directory` holds the corpus its `DIR` points at. The shipped
    constant is a `res://` path; this one is an OS path into the throwaway tree, which
    the reader accepts and no shipped loader could hold.
    """
    return "\n".join(
        [
            "class_name MeridianDefaults",
            "extends RefCounted",
            "",
            f'const DIR := "{directory}"',
            "",
        ]
    )


def _stage_meridian_corpus(root: Path, meridians) -> Path:
    """One `.tres` per fixture meridian, shaped like the shipped corpus files."""
    directory = root / "meridians"
    directory.mkdir(parents=True, exist_ok=True)
    for meridian_id, tier in meridians:
        (directory / f"{meridian_id}.tres").write_text(
            "\n".join(
                [
                    (
                        '[gd_resource type="Resource" script_class="MeridianDef"'
                        " load_steps=2 format=3]"
                    ),
                    "",
                    '[ext_resource type="Script" path="res://src/core/meridian_def.gd" id="1"]',
                    "",
                    "[resource]",
                    'script = ExtResource("1")',
                    f'id = &"{meridian_id}"',
                    f'display_name = "{meridian_id}"',
                    'type = &"primary"',
                    f"tier = {tier}",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    return directory


def _stage_qi_fixture() -> tuple[Path, Path, list, set[str]]:
    """A throwaway four-realm ladder: `(realm_dir, meridian_source, ladder, items)`."""
    root = Path(tempfile.mkdtemp(prefix="chaos_world_qi_gate_"))
    realm_dir = root / "qi" / "realms"
    realm_dir.mkdir(parents=True)
    meridian_source = root / "meridian_defaults.gd"
    items: set[str] = set()
    for row in FIXTURE_REALMS:
        realm_id = row[0]
        (realm_dir / f"{realm_id}.tres").write_text(_fixture_seed(row), encoding="utf-8")
        items.update(f"{realm_id}_{role}" for role in ("pill", "channel_elixir", "recovery_elixir"))
    meridian_source.write_text(
        _fixture_meridian_source(_stage_meridian_corpus(root, FIXTURE_MERIDIANS)),
        encoding="utf-8",
    )
    ladder_rows = [(realm_id, name, tier) for realm_id, name, tier, *_rest in FIXTURE_REALMS]
    return realm_dir, meridian_source, ladder_rows, items


def _qi_ladder_probes() -> list[str]:
    """Prove every qi gate-ladder rule fires, on a fixture invented for the purpose.

    Returns the labels of the rules that did not fire, so `run` fails the gate.
    """
    realm_dir, meridian_source, rows, items = _stage_qi_fixture()
    uncaught: list[str] = []
    try:
        baseline = audit.qi_gate_ladder_findings(
            rows, realm_dir=realm_dir, meridian_source=meridian_source, items=items
        )
        if baseline:
            raise ToolError(
                "the synthetic qi ladder does not start clean, so its mutations would prove"
                f" nothing: {'; '.join(baseline)}"
            )
        info("baseline: the synthetic qi ladder reports zero findings")

        # Bounded by the probe table's own length; every pass restores the whole
        # seed first, so no mutation can be masked by its predecessor (INC-0002).
        pristine = {
            path.name: path.read_text(encoding="utf-8") for path in realm_dir.glob("*.tres")
        }
        for realm_id, target, replacement, prefix in QI_GATE_PROBES:
            for name, text in pristine.items():
                (realm_dir / name).write_text(text, encoding="utf-8")
            if realm_id not in (PREMISE_STATE, PREMISE_TIERS):
                seed = realm_dir / f"{realm_id}.tres"
                text = seed.read_text(encoding="utf-8")
                if text.count(target) != 1:
                    raise ToolError(
                        f"{realm_id}: the fixture does not contain exactly one {target!r}"
                    )
                seed.write_text(text.replace(target, replacement), encoding="utf-8")
            findings = _qi_findings(realm_dir, meridian_source, rows, items, premise=realm_id)
            caught = [f for f in findings if prefix in f]
            label = f"{realm_id or 'premise'} -> {prefix}"
            if caught:
                info(f"caught  {label}: {caught[0][:140]}")
            else:
                uncaught.append(f"{label} (nothing matched)")
                info(f"MISSED  {label}: nothing matched `{prefix}`")
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)
    return uncaught


def _qi_findings(
    realm_dir: Path,
    meridian_source: Path,
    rows: list,
    items: set[str],
    premise: str = "",
) -> list[str]:
    """`qi_gate_ladder_findings` over the fixture, with every input aimed at it.

    A probe naming a PREMISE has no seed to break, so it points `ladder` at a file
    without the declaration that guard reads. That is how the unreadable-premise path
    is exercised: a guard whose premise cannot be read must say so rather than grade
    nothing — and an empty tier map grades as "no channel is unknown", which is a
    green so complete it hides the ladder (BL-0755).
    """
    if premise not in (PREMISE_STATE, PREMISE_TIERS):
        return audit.qi_gate_ladder_findings(
            rows, realm_dir=realm_dir, meridian_source=meridian_source, items=items
        )
    unreadable = realm_dir.parent / "no_declaration.gd"
    unreadable.write_text("# the premise this guard needs is not here\n", encoding="utf-8")
    name = "MERIDIAN_STATE" if premise == PREMISE_STATE else "MERIDIAN_DEFAULTS"
    saved = getattr(ladder, name)
    setattr(ladder, name, unreadable)
    try:
        # No `meridian_source`: the module global IS the premise under test, and
        # passing the fixture's own source would answer a question nobody asked.
        return audit.qi_gate_ladder_findings(rows, realm_dir=realm_dir, items=items)
    finally:
        setattr(ladder, name, saved)


# The three qi guards that read the RUNTIME, not the corpus (ADR 0194 / ADR 0195):
# a catalyst nothing consumes, a catalyst promoted into a gate, and a `cultivate`
# that is either free again or charges the one resource it is the sole source of.
#
# Each row is `(label, [(file, target, replacement), ...], finding prefix)`, plus
# an optional `items` suffix to drop from the known-item set. The files are a
# throwaway module fixture OUTSIDE the repo, so a probe can never mutate shipped
# data (INC-0007).
QI_PRICE_PROBES: tuple[tuple, ...] = (
    # A catalyst field no verb spends: the exact orphan ADR 0096 deleted, and the
    # one shape that let DEF-0040's 120 items sit craftable and pointless.
    (
        "dantian_catalyst consumed by nothing",
        [("training.gd", "seed.dantian_catalyst", "seed.meridian_catalyst")],
        "qi_catalyst_unconsumed",
    ),
    # The same for the other half of the restored family.
    (
        "meridian_catalyst consumed by nothing",
        [("training.gd", "seed.meridian_catalyst", "seed.dantian_catalyst")],
        "qi_catalyst_unconsumed",
    ),
    # ADR 0096's objection, made executable: a mandatory item in a gate position.
    (
        "a gate reads the dantian catalyst",
        [
            (
                "condition.gd",
                "return dantian.quality >= seed.dantian_quality_required",
                (
                    "return dantian.quality >= seed.dantian_quality_required and "
                    "_ITEMS.has_item(actor, seed.dantian_catalyst)"
                ),
            )
        ],
        "qi_catalyst_gated",
    ),
    # A seed that stops authoring the family at all.
    (
        "seed drops its dantian_catalyst",
        [("st_two.tres", 'dantian_catalyst = &"st_two_dantian_catalyst"', "")],
        "qi_catalyst_unauthored",
    ),
    # An authored id that resolves nowhere, so the verb that spends it refuses.
    # Every line the guard reads is still correct here: only the CONTENT changed,
    # which is why the probe carries the drop rather than an edit.
    (
        "dantian_catalyst resolves in no item",
        [],
        "qi_catalyst_item_missing",
        "st_two_dantian_catalyst",
    ),
    # ADR 0180's ruling restored by accident: the sitting is free again.
    (
        "cultivate stops calling its price",
        [("training.gd", "_buy_overflow_quality(actor, dantian, seed)", "_unpriced(actor)")],
        "qi_cultivate_unpriced",
    ),
    # The deadlock shape itself: the only verb that raises the reservoir also
    # lowers it, so it charges the resource it is the sole source of.
    (
        "cultivate drains the reservoir it fills",
        [
            (
                "training.gd",
                "\tdantian.fill(actor, gain)",
                "\tdantian.fill(actor, gain)\n\tdantian.drain(actor, 1.0)",
            ),
            ("transaction.gd", "pool.current = 0.0", "pool.current = pool.current"),
        ],
        "qi_price_self_deadlock",
    ),
)


def _fixture_training_source() -> str:
    """A throwaway `QiTraining`, shaped like the runtime's two priced verbs.

    It carries the shapes the guards read and nothing else: a `cultivate` that
    fills the reservoir and delegates its price to a private helper, a
    `train_off_gate_channel` that spends the other catalyst, and no gate read.
    """
    return "\n".join(
        [
            "class_name QiTraining",
            "extends RefCounted",
            "",
            'const _ITEMS := preload("res://src/modules/items/api.gd")',
            "",
            "",
            "static func cultivate(actor: Actor, amount: float) -> bool:",
            "\tvar dantian := QiAccess.dantian(actor)",
            "\tvar gain := amount",
            "\tvar overflow := 0.0",
            "\tdantian.fill(actor, gain)",
            "\tif overflow > 0.0:",
            "\t\t_buy_overflow_quality(actor, dantian, seed)",
            "\treturn true",
            "",
            "",
            (
                "static func _buy_overflow_quality(actor: Actor, dantian: Dantian, "
                "seed: QiRealmSeed) -> bool:"
            ),
            "\tif not _ITEMS.has_item(actor, seed.dantian_catalyst):",
            "\t\treturn false",
            "\tif not _ITEMS.consume_item(actor, seed.dantian_catalyst):",
            "\t\treturn false",
            "\tdantian.set_quality(dantian.quality + 0.05)",
            "\treturn true",
            "",
            "",
            "static func train_off_gate_channel(actor: Actor, meridian_id: StringName) -> bool:",
            '\tvar seed := QiRealmSeed.for_realm(&"st_one")',
            "\tif not _ITEMS.consume_item(actor, seed.meridian_catalyst):",
            "\t\treturn false",
            "\treturn true",
            "",
        ]
    )


def _fixture_transaction_source() -> str:
    """A throwaway transaction whose one qi write is the ascent's emptying."""
    return "\n".join(
        [
            "class_name QiBreakthroughTransaction",
            "extends RefCounted",
            "",
            "",
            "static func execute(actor: Actor) -> bool:",
            "\tvar pool := actor.resource(QiStats.QI)",
            "\tpool.current = 0.0",
            "\treturn true",
            "",
        ]
    )


def _fixture_condition_source() -> str:
    """A throwaway gate that reads state and no consumable beyond the pill."""
    return "\n".join(
        [
            "class_name QiBreakthroughCondition",
            "extends BreakthroughCondition",
            "",
            "",
            "func _dantian_ready(actor: Actor, seed: QiRealmSeed, dantian: Dantian) -> bool:",
            "\tif dantian.injured:",
            "\t\treturn false",
            "\treturn dantian.quality >= seed.dantian_quality_required",
            "",
        ]
    )


def _qi_price_probes() -> list[str]:
    """Prove every runtime-reading qi guard fires, on a fixture invented for it.

    Returns the labels of the rules that did not fire, so `run` fails the gate. A
    green guard is not a tested guard (INC-0016), and these three read live
    content — a guard asserting against content that has been fixed dies quietly.
    """
    realm_dir, meridian_source, rows, items = _stage_qi_fixture()
    root = realm_dir.parent
    # The ladder fixture's seeds carry the catalyst fields, and every realm owns
    # all five item ids, so the baseline below is genuinely clean.
    for path in realm_dir.glob("*.tres"):
        text = path.read_text(encoding="utf-8")
        realm_id = path.stem
        path.write_text(
            text.replace(
                f'recovery_item = &"{realm_id}_recovery_elixir"',
                (
                    f'recovery_item = &"{realm_id}_recovery_elixir"\n'
                    f'dantian_catalyst = &"{realm_id}_dantian_catalyst"\n'
                    f'meridian_catalyst = &"{realm_id}_meridian_catalyst"'
                ),
            ),
            encoding="utf-8",
        )
    items.update(f"{row[0]}_dantian_catalyst" for row in FIXTURE_REALMS)
    items.update(f"{row[0]}_meridian_catalyst" for row in FIXTURE_REALMS)
    sources = {
        "training.gd": _fixture_training_source(),
        "transaction.gd": _fixture_transaction_source(),
        "condition.gd": _fixture_condition_source(),
    }
    for name, text in sources.items():
        (root / name).write_text(text, encoding="utf-8")

    uncaught: list[str] = []
    try:
        baseline = _qi_price_findings(realm_dir, root, rows, items)
        if baseline:
            raise ToolError(
                "the synthetic qi module does not start clean, so its mutations would prove"
                f" nothing: {'; '.join(baseline)}"
            )
        info("baseline: the synthetic qi module reports zero findings")

        # Bounded by the probe table's own length, and every pass restores every
        # file first, so no mutation can be masked by its predecessor (INC-0002).
        pristine = {name: text for name, text in sources.items()} | {
            path.name: path.read_text(encoding="utf-8") for path in realm_dir.glob("*.tres")
        }
        for row in QI_PRICE_PROBES:
            label, edits, prefix = row[0], row[1], row[2]
            drop_item = row[3] if len(row) > 3 else None
            for name, text in pristine.items():
                _fixture_path(root, realm_dir, name).write_text(text, encoding="utf-8")
            known = set(items)
            if drop_item is not None:
                known.discard(drop_item)
            for name, target, replacement in edits:
                path = _fixture_path(root, realm_dir, name)
                text = path.read_text(encoding="utf-8")
                if target not in text:
                    raise ToolError(f"{label}: the fixture holds no {target!r}")
                path.write_text(text.replace(target, replacement), encoding="utf-8")
            findings = _qi_price_findings(realm_dir, root, rows, known)
            caught = [f for f in findings if prefix in f]
            if caught:
                info(f"caught  {label}: {caught[0][:140]}")
            else:
                uncaught.append(f"{label} (expected `{prefix}`)")
                info(f"MISSED  {label}: nothing matched `{prefix}`")
    finally:
        shutil.rmtree(root.parent, ignore_errors=True)
    return uncaught


def _fixture_path(root: Path, realm_dir: Path, name: str) -> Path:
    """Where a probe's edit lands: a seed inside the ladder, a module file beside it.

    One resolution for both, so a probe row that names a seed cannot quietly write
    a same-named file next to the seeds and prove nothing.
    """
    return realm_dir / name if name.endswith(".tres") else root / name


def _qi_price_findings(realm_dir: Path, root: Path, rows: list, items: set[str]) -> list[str]:
    """Both new guards over the fixture, with every input aimed at it."""
    return audit.qi_catalyst_findings(
        rows,
        realm_dir=realm_dir,
        items=items,
        training=root / "training.gd",
        condition=root / "condition.gd",
    ) + audit.qi_price_findings(training=root / "training.gd", transaction=root / "transaction.gd")


def run() -> int:
    realms = {realm_id for realm_id, _name, _tier in ladder_realms()}
    for realm_id, _scalar, _value, _prefix in MUTATIONS:
        if realm_id not in realms:
            raise ToolError(f"mutation names {realm_id}, which is not on the ladder")

    baseline = _validate_against(None)
    if baseline:
        raise ToolError(
            "the unmutated data does not validate, so a mutation cannot be shown to be"
            f" caught: {'; '.join(baseline)}"
        )
    info("baseline: real data validates clean")

    uncaught: list[str] = []
    staged = _stage()
    pristine = {path.name: path.read_text(encoding="utf-8") for path in staged.glob("*.tres")}
    try:
        for realm_id, scalar, value, prefix in MUTATIONS:
            # Restore every seed between mutations: they must not be able to mask each
            # other, and a mutation that only fires because of its predecessor's damage
            # has proved nothing about its own guard.
            for name, text in pristine.items():
                (staged / name).write_text(text, encoding="utf-8")
            _with_broken_scalar(staged, realm_id, scalar, value)
            findings = _validate_against(staged)
            caught = [f for f in findings if prefix in f]
            label = f"{realm_id}.{scalar} = {value}"
            if caught:
                info(f"caught  {label}: {caught[0][:140]}")
            else:
                uncaught.append(f"{label} (expected `{prefix}`)")
                info(f"MISSED  {label}: nothing matched `{prefix}`")
    finally:
        # The staged tree is the only thing written, and it is outside the repo.
        shutil.rmtree(staged.parent, ignore_errors=True)

    uncaught += _qi_ladder_probes()
    uncaught += _qi_price_probes()
    if uncaught:
        raise ToolError("a balance guard did not fire: " + "; ".join(uncaught))
    ok(
        f"all {len(MUTATIONS) + len(QI_GATE_PROBES) + len(QI_PRICE_PROBES)} balance guards fire on"
        " the mutation that breaks them"
    )
    return 0
