"""Red-path self-tests for the seed drift guard (DEF-0033).

Separate from `seed_write.py` for the reason `selftest_case.py` is separate from
`audit.py`: the guard is shipped code that `tools cultivation seed` imports, and
importing it must not register tests.

## Every case here is a synthetic fixture, never the shipped corpus

That is not squeamishness, it is the only safe direction. A red path sourced
from live content declares the rule dead the day somebody repairs the content,
which is how the acquisition selftest died and cost a day. So these build their
own two files in a temporary directory and point the guard at that: one the
generator authors in full, and one carrying a property the generator never emits
— the two classes the guard exists to tell apart.

The corpus half is deliberately absent. There is nothing to assert about the
shipped seed corpus here that `cultivation validate` does not already gate, and a
case that asserted "the shipped corpus is clean" would be a lie on day one: it
is NOT clean today (240 of 410 `seed` files and 450 of 660 `seed_systems` files
already disagree with their generator), which is precisely the drift this guard
now reports instead of hiding.
"""

from __future__ import annotations

import contextlib
import io
import tempfile
from pathlib import Path

from ..common import ToolError
from ..selftest import case, expect
from . import seed_write

#: A file the generator authors in full: every property here is one it emits.
PLAIN = (
    '[gd_resource type="Resource" script_class="FixtureSeed" load_steps=2 format=3]\n\n'
    '[ext_resource type="Script" path="res://src/fixture.gd" id="1"]\n\n'
    "[resource]\n"
    'script = ExtResource("1")\n'
    'id = &"fx_one"\n'
    "progress_required = 100.0\n"
)

#: The same file after a generator bug fix rewrote a value it DOES author.
DRIFTED = PLAIN.replace("progress_required = 100.0", "progress_required = 90.0")

#: A file that has outgrown the generator: it carries a property no generator
#: emits, so the generator cannot express what should replace it.
AUTHORED = PLAIN + "hand_tuned = 1.0\n"

FILES = {"plain.tres": PLAIN, "authored.tres": PLAIN}


def _fixture() -> tuple[tempfile.TemporaryDirectory, Path]:
    """A root holding both fixture files at exactly the generator's bytes."""
    raw = tempfile.TemporaryDirectory()
    root = Path(raw.name)
    for relative, content in FILES.items():
        path = root / relative
        path.write_text(content, encoding="utf-8")
    return raw, root


def _run(root: Path, **flags) -> tuple[int, str]:
    """Apply the guard, capturing everything it printed. Returns (code, output)."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
        code = seed_write.apply(FILES, root, label="fixture", **flags)
    return code, out.getvalue()


def _run_expecting_refusal(root: Path, **flags) -> str:
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            seed_write.apply(FILES, root, label="fixture", **flags)
    except ToolError:
        return out.getvalue()
    raise AssertionError("the guard ACCEPTED a corpus it must refuse")


@case("seed drift: a file the generator fully authors, hand-edited, FAILS naming the file")
def seed_drift_fails_loudly_naming_the_file() -> None:
    # THE DEF-0033 SHAPE. This is what the old `if path.exists(): continue` did
    # with it: `seed.run()` reported "created 0 ... existing resources preserved"
    # and exited 0 while the committed file disagreed with the generator.
    raw, root = _fixture()
    try:
        (root / "plain.tres").write_text(DRIFTED, encoding="utf-8")
        expect(
            (root / "plain.tres").read_text(encoding="utf-8") != PLAIN,
            "the fixture did not stage the edit this case is about",
        )

        result = seed_write.plan(root, FILES)
        expect(
            result.drift == ["plain.tres"] and not result.protected,
            f"an edited value the generator authors must classify as rewritable drift, got "
            f"drift={result.drift} protected={result.protected}",
        )

        output = _run_expecting_refusal(root)
        expect("plain.tres" in output, f"the failure did not NAME the file: {output!r}")
        expect(
            "progress_required" in output and "90.0" in output,
            f"the failure did not show the DIFFERENCE, only the file: {output!r}. A guard that "
            "names the path but not the change is an obstacle, not a guard",
        )
        expect(
            (root / "plain.tres").read_text(encoding="utf-8") == DRIFTED,
            "the refusal still wrote to disk, so it is not a refusal",
        )
    finally:
        raw.cleanup()


@case("seed drift: --force regenerates the file the generator fully authors")
def seed_force_rewrites_a_fully_authored_file() -> None:
    # The other direction, and the reason `--force` is not a blind overwrite: the
    # generator here knows every property in the file, so its version is complete
    # and re-applying it cannot lose anything.
    raw, root = _fixture()
    try:
        (root / "plain.tres").write_text(DRIFTED, encoding="utf-8")

        code, output = _run(root, force=True)

        expect(code == 0, f"--force must succeed, exited {code}: {output!r}")
        expect(
            (root / "plain.tres").read_text(encoding="utf-8") == PLAIN,
            "--force did not restore the generator's bytes",
        )
        expect(
            (root / "authored.tres").read_text(encoding="utf-8") == PLAIN,
            "--force rewrote a file it had no reason to touch",
        )
    finally:
        raw.cleanup()


@case("seed drift: --force REFUSES a file carrying a property the generator never emits")
def seed_force_refuses_an_outgrown_file() -> None:
    # The safety property, and the reason this is not a blanket overwrite.
    # Measured on the shipped corpus, a blind `--force` would have stripped
    # `fixed_modifiers`, `rarity`, `realm` and `roll_spec` from 420 item files
    # while reporting success. The generator has no value for a property it does
    # not emit, so writing its version is deletion.
    #
    # The refusal SKIPS rather than aborts: one outgrown file must not block the
    # rewrites the generator can do safely, or `--force` can never succeed on any
    # real corpus and gets deleted. The invariant under test is the FILE, not the
    # exit code — nothing was written to it, and it is named in the report.
    raw, root = _fixture()
    try:
        (root / "authored.tres").write_text(AUTHORED, encoding="utf-8")

        result = seed_write.plan(root, FILES)
        expect(
            result.protected == ["authored.tres"] and not result.drift,
            f"a file declaring an unemitted property must be protected, got "
            f"drift={result.drift} protected={result.protected}",
        )

        code, output = _run(root, force=True)

        expect(
            (root / "authored.tres").read_text(encoding="utf-8") == AUTHORED,
            "--force OVERWROTE a file carrying an authored property. That is the data loss this "
            "refusal exists to prevent",
        )
        expect(
            "hand_tuned" in output,
            f"the refusal did not name the property it refused to delete: {output!r}",
        )
        expect(
            "authored.tres" in output,
            f"the refusal did not name the file it skipped: {output!r}",
        )
        expect(
            code == 0,
            f"skipping an unrewritable file must not fail the run that CAN be applied, exited "
            f"{code}: {output!r}",
        )
    finally:
        raw.cleanup()


@case("seed drift: without --force, even a protected file stops the whole run")
def seed_protected_file_refuses_the_default_run() -> None:
    # The other half of the pair above, and the one that matters for DEF-0033: by
    # default NOTHING is written when the corpus disagrees, so the drift is
    # reported instead of quietly absorbed. `--force` is the informed opt-in; this
    # is the state a person lands in when they did not ask for it.
    raw, root = _fixture()
    try:
        (root / "authored.tres").write_text(AUTHORED, encoding="utf-8")

        output = _run_expecting_refusal(root)

        expect(
            "authored.tres" in output,
            f"the default run did not name the outgrown file: {output!r}",
        )
        expect(
            "will NOT touch these" in output or "delete authored content" in output,
            f"the refusal did not say why it refuses, so the reader cannot act on it: {output!r}",
        )
    finally:
        raw.cleanup()


@case("seed drift: --force applies what it can and skips only the outgrown file")
def seed_force_applies_what_it_can_despite_an_outgrown_file() -> None:
    # The defect this rule was corrected for. `--force` originally refused the
    # WHOLE run whenever any file was protected, which on the shipped corpus meant
    # 150 outgrown items blocked all 90 safe rewrites forever -- so the flag could
    # never do the job DEF-0033 asked for and would have been deleted on first use.
    # Partial application, with the residue named, is the behaviour that is both
    # useful and safe.
    raw, root = _fixture()
    try:
        (root / "plain.tres").write_text(DRIFTED, encoding="utf-8")
        (root / "authored.tres").write_text(AUTHORED, encoding="utf-8")

        code, output = _run(root, force=True)

        expect(
            (root / "plain.tres").read_text(encoding="utf-8") == PLAIN,
            "the file the generator fully authors was NOT regenerated, so --force is "
            "permanently unable to succeed and can never be used",
        )
        expect(
            (root / "authored.tres").read_text(encoding="utf-8") == AUTHORED,
            "the outgrown file was overwritten, which is the data loss this refuses",
        )
        expect(
            "authored.tres" in output and "plain.tres" in output,
            f"the run must report BOTH what it wrote and what it skipped: {output!r}",
        )
        expect(code == 0, f"a partial application is not a failure, exited {code}: {output!r}")
    finally:
        raw.cleanup()


@case("seed drift: an unmodified tree is a quiet no-op that writes nothing")
def seed_clean_tree_writes_nothing() -> None:
    # The case a careless implementation breaks first. A guard that fires on the
    # healthy state is one nobody reads, and a no-op that still rewrites bytes
    # churns the tree and dirties every seeded file on every run.
    raw, root = _fixture()
    try:
        result = seed_write.plan(root, FILES)
        expect(
            result.clean and not result.offending,
            f"a tree holding exactly the generator's bytes must be clean, got "
            f"drift={result.drift} protected={result.protected} create={result.create}",
        )

        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in sorted(root.iterdir())}

        code, output = _run(root)

        after = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in sorted(root.iterdir())}
        expect(code == 0, f"an unmodified tree must exit 0, exited {code}: {output!r}")
        expect(before == after, "a no-op run touched a file; it must write nothing at all")
        expect(
            "no changes" in output,
            f"a no-op run must SAY it was a no-op, so 'created 0' never reads as a task that "
            f"did nothing: {output!r}",
        )
        expect(
            not result.drift and not result.create,
            f"the fixture was not clean to begin with: {result}",
        )
    finally:
        raw.cleanup()


@case("seed drift: --dry-run reports the drift and still writes nothing")
def seed_dry_run_reports_without_writing() -> None:
    # A guard nobody can preview is an obstacle, not a guard. Exit 0 on purpose:
    # this is the report, and the refusal lives in the default mode.
    raw, root = _fixture()
    try:
        (root / "plain.tres").write_text(DRIFTED, encoding="utf-8")

        code, output = _run(root, dry_run=True)

        expect(code == 0, f"a preview must exit 0 even when it finds drift, exited {code}")
        expect("plain.tres" in output, f"the preview did not name the file: {output!r}")
        expect(
            (root / "plain.tres").read_text(encoding="utf-8") == DRIFTED,
            "--dry-run wrote to disk; it is a preview, not a repair",
        )
    finally:
        raw.cleanup()


@case("seed drift: a file the generator does not emit is never touched, even by --force")
def seed_never_touches_a_path_it_does_not_emit() -> None:
    # The ownership half of the rule. A hand-authored resource outside the
    # generator's map is not a candidate under any flag, so no amount of --force
    # can reach it. This is the invariant that lets `--force` exist at all.
    raw, root = _fixture()
    try:
        hand = root / "hand_authored.tres"
        hand.write_text('id = &"not_mine"\nhand_tuned = 3.0\n', encoding="utf-8")

        code, _ = _run(root, force=True)

        expect(code == 0, f"a clean tree plus an unowned file must exit 0, exited {code}")
        expect(
            hand.read_text(encoding="utf-8") == 'id = &"not_mine"\nhand_tuned = 3.0\n',
            "--force reached a file the generator does not emit",
        )
    finally:
        raw.cleanup()


@case("seed drift: a missing file is created, and only a missing one")
def seed_creates_a_missing_file() -> None:
    # The bootstrap's actual job, which the refusal must not have broken. Bounded
    # by the fixture's own two keys: one deleted, one untouched.
    raw, root = _fixture()
    try:
        (root / "plain.tres").unlink()

        result = seed_write.plan(root, FILES)
        expect(
            result.create == ["plain.tres"],
            f"a deleted file must classify as create, got {result.create}",
        )

        code, output = _run(root)

        expect(code == 0, f"bootstrapping a missing file must succeed, exited {code}: {output!r}")
        expect(
            (root / "plain.tres").read_text(encoding="utf-8") == PLAIN,
            "the missing file was not written from the generator's bytes",
        )
    finally:
        raw.cleanup()


@case("seed drift: the property reader sees top-level properties and not section headers")
def seed_property_reader_ignores_headers() -> None:
    # The reader the protected class is built on. If it matched a section header,
    # every generated file would look like it carried an unemitted property and
    # the whole guard would refuse everything - so this asserts both directions
    # on the exact text shape the generators emit.
    found = seed_write.properties(PLAIN)
    expect(
        found == {"script", "id", "progress_required"},
        f"the property reader returned {found}; the two section headers must not be read as "
        "properties, or every file reads as protected and nothing is ever rewritable",
    )
    expect(
        "gd_resource" not in found and "ext_resource" not in found,
        "a section header was read as a top-level property",
    )
    expect(
        seed_write.properties(AUTHORED) - seed_write.properties(PLAIN) == {"hand_tuned"},
        "an authored property was not detected, so the refusal this guard exists for cannot fire",
    )
