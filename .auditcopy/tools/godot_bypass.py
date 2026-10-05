"""`uv run python -m tools godot_bypass` — refuse committed automation that starts the
engine itself.

## Why

INC-0009 (kind=memory, open): six times in one work session an agent resolved the Godot
path by hand and ran it —

    $g = (Get-Content .godot-bin).Trim(); & $g --headless ...

— instead of `uv run python -m tools test`. That is the exact mechanism behind
INC-0004/INC-0005/INC-0008, where a probe that bypassed the tooling reached 73 GB resident
and forced a machine reset.

`tools/godot.py` is the whole safety story and it is a *process-level* story: `--log-file`
(so the engine stops writing 2 GB-per-file logs into the user's roaming profile),
`RAM_CEILING_BYTES` (kills at 12 GB), a wall-clock ceiling, a log-byte ceiling, and a
silence ceiling. A direct path invocation has NONE of them, so an allocating loop has no
guard at all — and a silent one passes every ceiling, because every ceiling except the
RAM one measures output and a silent run produces none.

There was no automated check that a bypass had not been committed. This is that check:
a static scan of the repository's OWN COMMITTED automation for the shapes that skip the
launcher.

## What it does NOT do

It does not stop anyone typing the command. It makes the *scripted* form hard to write by
accident, impossible to commit unnoticed, and attributable to a file and a line — which is
the difference between "somebody bypassed the tooling once" and a `git blame` answer.

It reads files. It never launches Godot, never imports `tools.godot`, never touches the
network. It belongs in `PREAMBLE_STEPS` for that reason: a guard about the machine-damage
hazard cannot depend on booting the engine (INC-0004).

## The false-positive budget

A permanently-red gate is a gate people learn to ignore, so every exemption here is
narrow, named, and justified rather than blanket:

* `tools/godot.py` — the resolver itself. It legitimately reads `.godot-bin`, reads
  `GODOT_BIN`, and searches `PATH` for `godot`/`godot4`; those three lines ARE the guard
  this scan enforces everywhere else. Exempted by exact path, not by "looks like the
  launcher".
* `tools/godot_bypass.py` and `tools/selftest_cases.py` — this guard and its red-path
  cases. A fixture that proves the rule fires has to BE the bypass, written out as a
  string; a rule set that cannot describe its own red path cannot be asserted on. Two
  exact paths, and adding a third has to be a deliberate edit here.
* `.agents/`, `.claude/`, `.commandcode/` — the harness-installed skill library, pinned by
  hash in `skills-lock.json` and pulled from an upstream GitHub repo. Those documents
  teach `godot --headless --script` for a project that is not this one; editing vendored
  upstream to satisfy a local rule is not a fix, and flagging them would make the gate
  permanently red the day a skill is re-synced.
* `.perch/` — machine-local memory written by a per-user agent indexer. One person's notes
  about one machine, not an artefact the repository's tooling owns.

Every exemption is one of the four kinds above and is returned with its reason, so
`tools godot_bypass` can never quietly drop a file category. What is exempt is
documented rather than silently narrowed: a guard with an unstated hole is worse than the
hazard it covers.

The two halves of the false-positive problem are the LOOKBEHIND and the FIRST DIVISOR in
the shapes below. The lookbehind refuses a preceding `.`, `/` or word character, so
`tools.godot`, `find_godot` and `project.godot` are not executable tokens. The first
divisor is mandatory, so a token butted straight against a word is not an invocation —
which is what keeps prose like "`godot-2d-movement` + `godot-tilemap`" and the eight
supported `godot.run_godot(...)` call sites out of the findings. A looser shape bridges a
sentence and flags every skill name in the repository; that version shipped and was
measured at eleven false positives before this rule was tightened.

* Documentation is exempt from the *config-path* and *env-resolve* rules and NOT from the
  *bare-invocation* rule. A doc that NAMES the rule (`AGENTS.md` says "goes through
  `tools/godot.py`", and `docs/handoff-foundation-gaps.md` says the resolver reads
  `.godot-bin`) is doing exactly what it should, while a doc that hands the next agent a
  runnable `godot ...` line is shipping the bypass. The distinction is whether the text
  carries an engine flag, which is decidable and not a matter of tone.

Outside scope, stated rather than implied: `.gd` (GDScript) and `.jsonl` files are not
scanned, so a doc comment in GDScript that documents a direct invocation is not reported.
The scan is over the repository's *automation*, which is Python plus the shell shapes
AGENTS.md forbids adding in the first place.
"""

from __future__ import annotations

import argparse
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .common import REPO_ROOT, ToolError, fail, info, ok

#: The repository this scans. A module global, not a local, so a test can point the guard
#: at a fixture tree — the same seam `mutation_history.REPO` exists for.
REPO: Path = REPO_ROOT

#: The committed automation, and the documentation that ships instructions alongside it.
#: `.gd` and `.jsonl` are deliberately absent; see the module docstring.
SCAN_SUFFIXES: tuple[str, ...] = (".py", ".ps1", ".bat", ".cmd", ".sh", ".md")

#: The resolver. Reads `.godot-bin`, reads `GODOT_BIN`, and runs `shutil.which("godot")` —
#: so it trips all three rules and is exempt by exact path.
RESOLVER = "tools/godot.py"

#: Harness-installed skill libraries: vendored upstream, hash-pinned in `skills-lock.json`,
#: and written for other Godot projects. Not this repository's automation.
VENDORED_PREFIXES: tuple[str, ...] = (".agents/", ".claude/", ".commandcode/")

#: Machine-local memory written by a per-user agent indexer. Not this repository's
#: automation either, and not the same thing as the vendored skills: it is one person's
#: notes about this machine, and a finding there would be one the gate asks somebody else
#: to fix by editing a file the gate does not own.
LOCAL_PREFIXES: tuple[str, ...] = (".perch/",)

#: Files that hold the GUARD, and therefore have to name the bypass shapes they are
#: forbidden to find: a self-test fixture is the bypass, written as a string, and a rule
#: set that cannot describe its own red path cannot be asserted on. Narrow on purpose —
#: three exact paths, and the resolver below is one of them. Anything else that needs to
#: ship a bypass example must be added here deliberately, which is the point.
SELF_EXEMPT: tuple[str, ...] = ("tools/godot_bypass.py", "tools/selftest_cases.py")

#: A Godot executable token, in the spellings an agent actually reaches for: the PATH name
#: (`godot`, `godot4`), the Windows release asset (`Godot_v4.7.2-stable_win64.exe`) and a
#: renamed copy (`godot.exe`, `Godot.exe`). The lookbehind refuses a preceding `.`, `/` or
#: word character, so `tools.godot`, `find_godot` and `project.godot` are not tokens.
_GODOT_TOKEN = (
    r"(?<![A-Za-z0-9_.\-/\\])(?:godot4|godot|[Gg]odot_v[0-9][\w.\-]*|[Gg][Oo][Dd][Oo][Tt]\.exe)"
)

#: Nothing that divides one word from another. A prose line about a skill named
#: `godot-2d-movement`, a Python module path like `godot.run_godot`, or a sentence that
#: happens to contain the word "import" further along must not be able to bridge the two.
#: Every shape below is anchored at a token and may cross only this, and the FIRST one is
#: not optional: an executable always has something separating it from its arguments, so a
#: token butted straight against a word is not an invocation.
_FIRST_DIVISOR = r"""[ \t"'`][ \t"']*,?[ \t"']*"""

#: Flags that only mean "I am starting the engine". Long flags only, and deliberately NOT
#: a bare `-\w`: `-2` in `godot-2d-movement` is a hyphen-digit inside a hyphenated name, so
#: a short-flag catch-all matches prose. Every bypass worth refusing spells `--headless`.
_ENGINE_FLAG = (
    r"(?:--headless|--path|--script|--import|--editor|--quit|--quit-after|--export[\w-]*"
    r"|--main-pack|--main-loop|--check-only|--build-solutions|--doctool|--benchmark"
    r"|--write-movie|--version)"
)

#: Up to four non-dividing gaps between the executable and the flag. Bounded and narrow so
#: the shape cannot reach across a sentence; a shell line has one gap, a Python argv list
#: has two, and four is comfortable without ever bridging prose.
_GAP = rf"(?:{_FIRST_DIVISOR}(?:[^\n]{{0,60}}?{_FIRST_DIVISOR}){{0,3}})?"

#: Execution contexts. A Godot token sitting in one of these is being *resolved or run*
#: even with no flag on the line (`Get-Command godot`, `shutil.which("godot")`,
#: `Start-Process $exe`), which is the half of the shape that resolves nothing useful and
#: starts everything. `run(` is last in the alternation so `run_godot(` is tried first by
#: the engine's leftmost-match rule and never reaches it — that ordering is what keeps the
#: eight `godot.run_godot(...)` call sites in this repository out of the findings.
_EXEC_CONTEXT = (
    r"(?:&\s*|Start-Process\s+|Invoke-Expression\s+|Invoke-Command\s+|sudo\s+|exec\s+|call\s+"
    r"|shutil\.which\(\s*|os\.system\(\s*|os\.popen\(\s*|Popen\(\s*|run\(\s*"
    r"|check_output\(\s*|check_call\(\s*|get_command\(\s*|Start\s*)"
)

##: `(rule id, why, fix, regex, applies-to-suffixes)`. One table, so the finding and the
##: explanation cannot drift apart, and so every rule is visible in one read.
SHAPES: tuple[tuple[str, str, str, re.Pattern[str], frozenset[str]], ...] = (
    (
        "godot-bypass:config-path",
        "reads `.godot-bin`, the gitignored machine-local file `find_godot()` owns. Reading "
        "it is the first half of INC-0009's six invocations: the path is then launched by "
        "hand, so nothing the launcher does applies.",
        "call `tools.godot.run_godot([...])` — or drive the suite with "
        "`uv run python -m tools test --suite <name>`, which is the supported path.",
        re.compile(r"\.godot-bin"),
        frozenset({".py", ".ps1", ".bat", ".cmd", ".sh"}),
    ),
    (
        "godot-bypass:env-resolve",
        "resolves `GODOT_BIN` itself. AGENTS.md: 'anything that resolves GODOT_BIN itself' "
        "gets no ceiling — the ceiling lives in the launcher's process, not in the path.",
        "`from tools.godot import find_godot, run_godot` and let the launcher own the "
        "resolution and every ceiling with it.",
        re.compile(r"(?<![A-Za-z0-9_])GODOT_BIN(?![A-Za-z0-9_])"),
        frozenset({".py", ".ps1", ".bat", ".cmd", ".sh"}),
    ),
    (
        "godot-bypass:bare-invocation",
        "hands the Godot binary an engine flag. This is a direct invocation: no "
        "`--log-file` redirect, no RAM ceiling, no wall-clock ceiling, no log-byte "
        "ceiling, no silence ceiling (INC-0004/0005/0008/0009). The executable is a plain "
        "name or a `$var` — `& $g` after a `.godot-bin` read IS a launch and cannot be "
        "told apart from one by the variable's name.",
        "`uv run python -m tools test --suite <name>` to run a suite; `tools run`, "
        "`tools ui drive`, `tools export <preset>` for the rest. If you need to see an "
        "error the tool swallowed, read `build/logs/` — never re-run the engine unguarded.",
        re.compile(rf"(?:{_GODOT_TOKEN}|\$[A-Za-z_]\w*){_GAP}{_ENGINE_FLAG}"),
        frozenset(SCAN_SUFFIXES),
    ),
    (
        "godot-bypass:execution-context",
        "puts a Godot executable into an execution context with no flag to recognise it by "
        "(`Get-Command godot`, `shutil.which('godot')`, `Start-Process $exe`). Flagless "
        "and therefore invisible to the bare-invocation rule, and just as unguarded.",
        "resolve through `tools.godot.find_godot()` and launch through `run_godot()`, which "
        "is the only place a Godot process is allowed to be created.",
        re.compile(rf"{_EXEC_CONTEXT}\s*[\"']?{_GODOT_TOKEN}"),
        frozenset({".py", ".ps1", ".bat", ".cmd", ".sh"}),
    ),
)

#: Files bigger than this are not scanned. A megabyte of documentation is not where a
#: six-line bypass lives, and the guard has to stay fast enough to sit in the preamble.
MAX_FILE_BYTES = 512 * 1024

#: How many findings to print before summarising the rest. An unbounded print is a wall of
#: text nobody reads, which is how a real finding gets lost in noise.
MAX_REPORTED = 20


@dataclass(frozen=True)
class Finding:
    """One bypass shape, at a file and line, so it can be found and fixed."""

    path: str
    line: int
    rule: str
    why: str
    fix: str
    text: str

    def describe(self) -> str:
        return f"{self.path}:{self.line}  [{self.rule}]\n      {self.text}\n      {self.why}"

    @property
    def excerpt(self) -> str:
        """The offending line, trimmed to fit one report row."""
        return self.text.strip()[:120]


def candidate_files(root: Path) -> tuple[Path, ...]:
    """Every committed file this guard reads, as repo-relative posix paths.

    Git is the file list rather than a filesystem walk, for two reasons. It is what makes
    the scan about COMMITTED automation: a scratchpad probe or an uncommitted editor buffer
    is not something a colleague's `tools check` has to answer for. And it is the same
    `git ls-files` one-subprocess cost `mutation_history` already pays.
    """
    pathspecs = [f"*{suffix}" for suffix in SCAN_SUFFIXES]
    listed = subprocess.run(  # noqa: S603 - fixed argv, no shell
        ["git", "ls-files", "-z", "--", *pathspecs],
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
    )
    if listed.returncode != 0:
        raise ToolError(
            "cannot list the repository's committed files, so the bypass guard cannot "
            f"prove anything: {listed.stderr.strip() or listed.returncode}"
        )
    return tuple(
        entry
        for entry in listed.stdout.split("\0")
        if entry and entry.endswith(SCAN_SUFFIXES) and not exempt(entry)
    )


def exempt(path: str) -> str | None:
    """Why this file is out of scope, or None when it is in scope.

    Narrow on purpose. `RESOLVER` and `SELF_EXEMPT` are exact paths and the two prefix
    tuples are whole directories that belong to another project or to one machine. Nothing
    else is excluded — a guard that silently drops a category of file is a guard with an
    unstated hole in it.
    """
    if path == RESOLVER:
        return (
            "it IS the resolver: reading `.godot-bin` and `GODOT_BIN` is this file's job, "
            "and it is the only thing every other rule here routes toward"
        )
    if path in SELF_EXEMPT:
        return (
            "it holds this guard, so it has to be able to NAME the bypass shapes it is "
            "forbidden to find: a red-path fixture is the bypass written as a string"
        )
    for prefix in VENDORED_PREFIXES:
        if path.startswith(prefix):
            return (
                f"{prefix} is the harness-installed skill library pinned by hash in "
                "skills-lock.json and vendored from upstream for OTHER Godot projects; "
                "it is not this repository's automation and must not be edited to satisfy "
                "a local rule"
            )
    for prefix in LOCAL_PREFIXES:
        if path.startswith(prefix):
            return (
                f"{prefix} is machine-local agent memory written by a per-user indexer, "
                "not a committed artefact this repository's tooling owns"
            )
    return None


def scan_text(path: str, text: str) -> list[Finding]:
    """Every bypass shape in one file, in line order."""
    suffix = Path(path).suffix
    lines = text.splitlines()
    found: list[Finding] = []
    for rule_id, why, fix, pattern, suffixes in SHAPES:
        if suffix not in suffixes:
            continue
        for number, line in enumerate(lines, 1):
            match = pattern.search(line)
            if match is None:
                continue
            found.append(
                Finding(
                    path=path,
                    line=number,
                    rule=rule_id,
                    why=why,
                    fix=fix,
                    text=line.strip(),
                )
            )
            break  # one report per rule per file: the first hit is the one to fix
    return sorted(found, key=lambda f: (f.line, f.rule))


def scan(root: Path | None = None) -> tuple[int, list[Finding]]:
    """Read the committed automation under `root`; return (files read, findings).

    The count is returned rather than recomputed by the caller so the `ok` line cannot
    report a different population from the one that was actually scanned.
    """
    base = REPO if root is None else root
    relatives = candidate_files(base)
    found: list[Finding] = []
    for relative in relatives:
        path = base / relative
        try:
            if path.stat().st_size > MAX_FILE_BYTES:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            raise ToolError(f"could not read {relative}: {exc}") from None
        found.extend(scan_text(relative, text))
    return len(relatives), sorted(found, key=lambda f: (f.path, f.line))


def register(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "godot_bypass",
        help="fail if committed automation starts the Godot binary instead of tools/godot.py",
    )
    parser.add_argument(
        "--root",
        default=None,
        help="scan this repository root instead of the one this tool lives in",
    )


def run(args: argparse.Namespace) -> int:
    root = Path(args.root) if getattr(args, "root", None) else REPO
    read, findings = scan(root)

    if not findings:
        ok(
            f"no committed script starts the Godot binary directly "
            f"({read} automation/doc files read; every run goes through tools/godot.py)"
        )
        return 0

    fail(
        f"{len(findings)} committed file(s) bypass tools/godot.py — INC-0009, the mechanism "
        "behind INC-0004/0005/0008 and the 73 GB reset"
    )
    for finding in findings[:MAX_REPORTED]:
        info(finding.describe())
    if len(findings) > MAX_REPORTED:
        info(f"  ... and {len(findings) - MAX_REPORTED} more.")
    info(
        "  Each of these has no --log-file redirect (2 GB-per-file logs into the user "
        "profile), no RAM_CEILING_BYTES at 12 GB, no wall-clock ceiling, no log-byte "
        "ceiling and no silence ceiling, because every one of those lives in the launcher "
        "process and a direct invocation does not have it. Use "
        "`uv run python -m tools test --suite <name>`, `tools run`, `tools ui drive` or "
        "`tools export`; to see an error the tool swallowed, read `build/logs/`."
    )
    return 1
