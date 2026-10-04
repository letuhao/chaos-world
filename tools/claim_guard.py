"""`uv run python -m tools claim_guard check|claim|release|report` — refuse two live
sessions owning one path (INC-0023).

## Why

INC-0023: a sub-agent call returned an EMPTY tool result rather than an error. The
coordinator read the empty result as a failed launch and re-sent the IDENTICAL prompt,
so two live sessions held the same two files (`loot_reward_list.gd`,
`loot_drop_row.gd`). Nothing was lost — the second agent was stood down before it wrote —
but that window is precisely the write-write collision INC-0003 exists to prevent, and
the coordinator broke the rule it had just briefed the agents on.

Every other guard in this repository is enforced by *policy plus review*: INC-0003 is
`mitigated`, not `resolved`, because "do not bulk-revert" cannot be observed by a tool
that reads files. THIS one can be. A session that owns paths writes them into a committed
ledger, and a gate reads the ledger — so the second dispatch is refused before the second
agent exists rather than after it has been briefed, has read the files, and has a brief
worth twenty minutes.

## The one question this gate may ask

INC-0017 is the design flaw to not repeat. `mutation_history` first asked whether a probe
was EVER COMMITTED; history is immutable, so the answer is permanently yes once true and
`tools check` can never pass again. A gate whose answer is an immutable historical fact is
worth less than no gate — the first agent who sees it red and unfixable downgrades it or
deletes it, and both destroy the protection.

So the question here is about CURRENT, REPAIRABLE STATE: *does the ledger as it stands
right now carry two live sessions claiming overlapping paths?* Hand-editing a line clears
it. It is the same ref-tip question `mutation_history` was redesigned around, applied to a
file rather than to git.

That is also why the ledger **must** be committed: an uncommitted ledger is a local file
that does not exist on the runner's checkout, where it would read as an EMPTY ledger —
which is clean, and green, and is the same "reports ok because it looked at nothing"
failure INC-0013 paid for.

## Stale claims are reported, never fatal

`STALE_AFTER` is the ceiling past which a claim is reported as stale instead of as a
conflict. A dead session that never released its paths would otherwise pin this gate red
forever, and the first agent to hit that downgrades or deletes the guard — INC-0017 with a
ledger instead of a git ref. Staleness is advisory (`warn`, exit 0): an over-age claim is
noise to clear, not a hazard, because nothing can be written against a session that is not
answering.

The ceiling is **8 hours**, chosen from this repository's measured facts rather than a
round number:

* a whole-suite `tools test` cycle is minutes, and the measured lock-hold in INC-0018 ran
  **continuously for over 40 minutes** with the holder changing each poll, so several hours
  of real work is normal for one session;
* an agent in this fleet has gone **62 minutes idle with two parse errors** still holding
  its paths (INC-0011), which is the low side, not the high;
* an unattended overnight pause is real on a machine other people also use.

Below about 4h a legitimately slow session gets reported as a conflict on paths that are
genuinely still its own, and the cost of that is an agent stalled mid-slice while its
heartbeat is 5 hours old. Above about 24h the ledger stops being evidence of anything
live and the guard degenerates into a wall of stale warnings nobody reads — which is the
same as no guard, because everything gets ignored. 8h clears a crashed session in one
working day and clears a genuinely abandoned one before it can mislead anyone.

## What it does NOT do

It does not know whether a session is alive; the heartbeat is self-reported, because
nothing else in this tree can observe one. It does not police the working tree: a session
that never claimed a path can still collide (INC-0023's guard is preventive, not
forensic), and a session that claimed a path can still be stomped. And it does not claim
INC-0023 is closed — `docs/incidents.jsonl` still says `watching`, because the durable
half (the record of the claim) is what this ships, and the second half (every dispatch
actually claiming) is a discipline the ledger cannot enforce on an agent that ignores it.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

from .common import DOCS_DIR, ToolError, fail, info, ok, warn

#: The ledger. Committed, like `docs/deferred.jsonl` and `docs/incidents.jsonl`, because
#: the guard has to answer the same question on CI as it does here. `docs/` rather than a
#: gitignored runtime path: an uncommitted ledger does not exist on the runner's checkout
#: and would read as an empty — that is, clean — ledger.
CLAIMS_PATH: Path = DOCS_DIR / "claims.jsonl"

#: Every line carries these. One JSON object per line, the shape `docs/deferred.jsonl` and
#: `docs/incidents.jsonl` use, so it is one ledger vocabulary for the whole repository.
#: `owner`, `module` and `note` are free and ignored by the guard; they are what a human
#: reads to decide which of two colliding sessions to stand down.
REQUIRED: tuple[str, ...] = ("session", "paths", "heartbeat")

#: Monotonic enough for a heartbeat and impossible to confuse with a date: ISO 8601 with a
#: zone offset. The fractional part is OPTIONAL because `datetime.isoformat()` writes it by
#: default — a pattern demanding whole seconds would reject this tool's own output, which is
#: what the first version of this guard did and what the fixture run below caught.
STAMP = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2}|Z)"

#: How long a session may hold paths without refreshing its heartbeat. See the module
#: docstring for the measurement this number comes from. Stale is `warn`, not `fail`.
STALE_AFTER = timedelta(hours=8)

#: How many overlapping pairs to print before summarising the rest. With ~20 live agents a
#: full cross-product is a wall of text nobody reads, and the first agent to read a wall
#: of text reads none of it.
MAX_REPORTED = 12


@dataclass(frozen=True)
class Claim:
    """One session's ledger line: the id it is known by, the paths it owns, and when it
    last said it still owned them."""

    session: str
    paths: tuple[str, ...]
    heartbeat: datetime

    def age(self, now: datetime) -> timedelta:
        return now - self.heartbeat


@dataclass(frozen=True)
class Overlap:
    """Two LIVE claims sharing at least one path. Both sides are named, because the fix is
    a stand-down and the answer to "which of these two do I stop" needs both ids."""

    left: Claim
    right: Claim
    shared: str

    def describe(self) -> str:
        return f"{self.left.session}  x  {self.right.session}   share  {self.shared}"


def _now() -> datetime:
    return datetime.now(UTC)


def normalize(raw: str, session: str) -> str:
    """One repository-relative POSIX path, or a ToolError naming who sent it.

    Every separator, leading `./` and trailing slash is normalised away BEFORE the ledger
    is written, so `game/src//modules/loot/` and `game/src/modules/loot` are one claim on
    disk rather than two spellings that a segment comparison treats as unrelated. A path
    outside the repository, or one naming `..`, is refused rather than normalised: those are
    what makes an overlap comparison mean anything at all.
    """
    text = raw.strip().replace("\\", "/")
    if text.startswith("./"):
        text = text[2:]
    parts = [part for part in text.split("/") if part not in ("", ".")]
    if not parts:
        raise ToolError(f"{session}: '{raw}' names no path")
    if any(part == ".." for part in parts):
        raise ToolError(
            f"{session}: '{raw}' reaches outside the repository with '..', and a claim that "
            "leaves the tree cannot be compared against anybody else's"
        )
    return "/".join(parts)


def overlaps(left: str, right: str) -> bool:
    """True when two claimed paths are equal, or one CONTAINS the other.

    Comparison is per PATH SEGMENT, and that is the whole point of this module. A
    directory claim must cover a file claimed inside it — `game/src/modules/loot` against
    `game/src/modules/loot/loot_drop_row.gd` is the collision INC-0023 was, and only the
    containment direction is what catches it.

    It is deliberately NOT `str.startswith`. `game/src/modules/loot` is a byte prefix of
    `game/src/modules/loot2/loot_state.gd`, so the naive test makes two unrelated modules
    conflict forever and the first agent to meet that stops claiming directories at all —
    a guard that reports neighbours as collisions trains its users to ignore it. Comparing
    tuples of segments makes the containment exact: equal prefix ⇒ overlap, anything else
    ⇒ disjoint.
    """
    a = tuple(left.split("/"))
    b = tuple(right.split("/"))
    shared = min(len(a), len(b))
    return a[:shared] == b[:shared]


def _same_holder(left: Claim, right: Claim) -> bool:
    """True when two claims belong to one session.

    A session that lists `a.gd` and `a/b.gd` is one holder naming two nested paths, not two
    holders colliding. Failing on it would make the honest, careful claim (name the
    directory AND the files you are touching inside it) the only way to go red.
    """
    return left.session == right.session


def read_claims(path: Path | None = None) -> list[Claim]:
    """Parse the ledger. Returns `[]` for a file that does not exist, which is a real
    state and a clean verdict.

    It is NOT treated as a skip: the guard reports zero claims rather than declining to
    run, so "the ledger is empty" is visibly an answer and not a silence. What is NOT
    tolerated is a ledger that exists and cannot be parsed — a torn write on a shared tree
    is reported with its line number and its author, because a guard that skips an
    unreadable ledger can never tell the reader that it read nothing.
    """
    target = CLAIMS_PATH if path is None else path
    if not target.is_file():
        return []
    text = target.read_text(encoding="utf-8")
    rows = [_parse(line, number, target) for number, line in enumerate(text.splitlines(), 1)]
    return [claim for claim in rows if claim is not None]


def _parse(line: str, number: int, path: Path) -> Claim | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("//"):
        return None
    try:
        entry = json.loads(stripped)
    except json.JSONDecodeError as exc:
        raise ToolError(
            f"{path.name}:{number}: invalid JSON: {exc}. Every line is one claim object; "
            "a torn write here would read as a claim nobody owns"
        ) from exc
    if not isinstance(entry, dict):
        raise ToolError(
            f"{path.name}:{number}: a claim is a JSON object, got {type(entry).__name__}"
        )

    missing = [field for field in REQUIRED if not entry.get(field)]
    if missing:
        raise ToolError(
            f"{path.name}:{number}: claim from {entry.get('session', '?')!r} is missing "
            f"{missing} — a claim without a heartbeat expires on the first run and without "
            "paths it claims nothing"
        )
    session = str(entry["session"]).strip()
    if not session:
        raise ToolError(
            f"{path.name}:{number}: 'session' is empty, so nothing can stand this claim down"
        )

    raw_paths = entry["paths"]
    if not isinstance(raw_paths, list) or not raw_paths:
        raise ToolError(
            f"{path.name}:{number}: {session} lists no paths. "
            "'paths' is a list, and an empty one is what release sets"
        )
    paths = tuple(normalize(str(raw), session) for raw in raw_paths)

    if not re.fullmatch(STAMP, str(entry["heartbeat"])):
        raise ToolError(
            f"{path.name}:{number}: {session} heartbeat {entry['heartbeat']!r} is not ISO 8601 "
            f"with a zone ({STAMP}). The age of a claim is the only thing that retires it, "
            "and an unreadable timestamp has to fail rather than default to 'fresh'"
        )
    heartbeat = datetime.fromisoformat(str(entry["heartbeat"]).replace("Z", "+00:00"))
    if heartbeat.tzinfo is None:
        raise ToolError(f"{path.name}:{number}: {session} heartbeat has no UTC offset")

    return Claim(session=session, paths=paths, heartbeat=heartbeat.astimezone(UTC))


def conflicts(claims: list[Claim]) -> list[Overlap]:
    """Every overlapping pair among the claims given.

    Staleness is decided by the caller, not here, so this function is a pure question
    about two sets of paths and can be asserted on directly in a self-test.

    `shared` carries BOTH sides of the overlap, not the shorter one. A directory claim
    against a file inside it is one collision written two ways, and the reader deciding
    which session to stand down needs to see the directory claim AND the file claim;
    printing only the directory reads as though the two sessions agreed on a folder.
    """
    found: list[Overlap] = []
    for index, left in enumerate(claims):
        for right in claims[index + 1 :]:
            if _same_holder(left, right):
                continue
            shared = sorted(
                {path for a in left.paths for b in right.paths if overlaps(a, b) for path in (a, b)}
            )
            if shared:
                found.append(Overlap(left=left, right=right, shared=", ".join(shared)))
    return sorted(found, key=lambda pair: (pair.left.session, pair.right.session))


def split_stale(
    claims: list[Claim], now: datetime | None = None
) -> tuple[list[Claim], list[Claim]]:
    """(live, stale). A claim older than `STALE_AFTER` is stale, not live.

    Time moves backwards (a clock correction, a DST-free UTC comparison against a
    differently-configured machine) can make a fresh heartbeat look slightly in the future;
    the answer is to treat it as live. Retiring a live claim because the clock wobbled is
    exactly the window INC-0023 is about.
    """
    moment = _now() if now is None else now
    live = [claim for claim in claims if claim.age(moment) <= STALE_AFTER]
    stale = [claim for claim in claims if claim.age(moment) > STALE_AFTER]
    return live, stale


def write_claims(claims: list[Claim], path: Path | None = None) -> Path:
    """Rewrite the ledger atomically.

    `docs/incidents.jsonl` and `docs/deferred.jsonl` are rewritten whole. That is correct
    for an append-shaped history and wrong for a live ledger: two coordinators claiming at
    the same moment would each read, each rewrite, and one claim would vanish with no trace.
    """
    target = CLAIMS_PATH if path is None else path
    rows = "".join(
        json.dumps(
            {
                "session": claim.session,
                "paths": list(claim.paths),
                "heartbeat": claim.heartbeat.isoformat(),
            },
            ensure_ascii=False,
        )
        + "\n"
        for claim in claims
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    staging = target.with_name(f"{target.name}.{os.getpid()}.tmp")
    staging.write_text(rows, encoding="utf-8")
    os.replace(staging, target)
    return target


def _arg_paths(raw: str) -> tuple[str, ...]:
    return tuple(part for part in re.split(r"[,\s]+", raw.strip()) if part)


def register(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "claim_guard",
        help="fail if two live agent sessions claim overlapping paths (INC-0023)",
    )
    actions = parser.add_subparsers(dest="claim_action", required=True)

    check = actions.add_parser("check", help="fail on two live claims over one path (the gate)")
    check.add_argument(
        "--ledger",
        default=None,
        help="read this ledger instead of docs/claims.jsonl (used by the self-tests)",
    )
    check.add_argument(
        "--fail-on",
        choices=("warn", "error"),
        default="error",
        help="'warn' reports conflicts without failing (default: error)",
    )

    claim = actions.add_parser("claim", help="record or extend this session's claim")
    claim.add_argument("--session", required=True, help="the id this session is known by")
    claim.add_argument(
        "--paths", required=True, help="repo-relative paths, comma or space separated"
    )
    claim.add_argument(
        "--ledger",
        default=None,
        help="write this ledger instead of docs/claims.jsonl (used by the self-tests)",
    )

    release = actions.add_parser("release", help="drop paths, or the whole session")
    release.add_argument("--session", required=True)
    release.add_argument(
        "--paths",
        default="",
        help="paths to drop; omit to release EVERY path this session holds",
    )
    release.add_argument("--ledger", default=None)

    report = actions.add_parser("report", help="print every claim with its age")
    report.add_argument(
        "--ledger",
        default=None,
        help="read this ledger instead of docs/claims.jsonl (used by the self-tests)",
    )


def _describe_claim(claim: Claim, now: datetime) -> str:
    age = claim.age(now)
    hours = age.total_seconds() / 3600
    return f"  {claim.session}  {hours:+.1f}h  {', '.join(claim.paths)}"


def _run_check(args: argparse.Namespace) -> int:
    path = Path(args.ledger) if getattr(args, "ledger", None) else CLAIMS_PATH
    claims = read_claims(path)
    now = _now()
    live, stale = split_stale(claims, now)
    found = conflicts(live)

    if stale:
        # Reported every run, never fatal. See the module docstring: this is the INC-0017
        # mechanism wearing a different hat, and a claim nobody can clear is not a gate.
        warn(
            f"{len(stale)} claim(s) older than {int(STALE_AFTER.total_seconds() // 3600)}h "
            f"are stale and are NOT counted as conflicts — their session may still be writing"
        )
        for claim in stale:
            warn(_describe_claim(claim, now))

    if not found:
        ok(
            f"no two live sessions claim overlapping paths "
            f"({len(live)} live claim(s) over {sum(len(c.paths) for c in live)} path(s), "
            f"{len(stale)} stale — INC-0023)"
        )
        return 0

    detail = (
        "Two live sessions own the same path. One module gets one owner: stand one of them "
        "down before it writes, and if the dispatch that created it looked like it failed, "
        "read the sessionID out of the previous tool result instead of resending — an "
        "empty body is ambiguous, not a failure (INC-0023). Release with "
        "`tools claim_guard release --session <id>`."
    )
    if args.fail_on == "error":
        fail(
            f"{len(found)} overlapping live claim(s) — INC-0023, the write-write collision "
            f"INC-0003 exists to prevent"
        )
    for pair in found[:MAX_REPORTED]:
        fail(f"  {pair.describe()}")
    if len(found) > MAX_REPORTED:
        fail(f"  ...and {len(found) - MAX_REPORTED} more.")
    if args.fail_on == "error":
        info(detail)
        return 1
    info(detail)
    return 0


def _run_claim(args: argparse.Namespace) -> int:
    path = Path(args.ledger) if getattr(args, "ledger", None) else CLAIMS_PATH
    wanted = [normalize(raw, args.session) for raw in _arg_paths(args.paths)]
    if not wanted:
        raise ToolError("claim needs --paths")

    claims = read_claims(path)
    now = _now()
    mine = next((claim for claim in claims if claim.session == args.session), None)
    if mine is None:
        claims.append(Claim(session=args.session, paths=tuple(wanted), heartbeat=now))
        action = "recorded"
    else:
        # Union, not replace: claiming one more file must not silently release the rest.
        claims[claims.index(mine)] = Claim(
            session=args.session,
            paths=tuple(dict.fromkeys(mine.paths + tuple(wanted))),
            heartbeat=now,
        )
        action = "refreshed"

    write_claims(claims, path)

    # The refusal has to be visible at the moment of claiming, because that is the only
    # moment somebody can still stand a session down. The gate catches the same overlap
    # later; this is what stops it being created.
    live, stale = split_stale(claims, now)
    found = [
        pair for pair in conflicts(live) if args.session in (pair.left.session, pair.right.session)
    ]
    for pair in found:
        other = pair.left if pair.right.session == args.session else pair.right
        warn(f"{args.session} now overlaps {other.session}  ({pair.shared})")
    if stale:
        warn(f"{len(stale)} other claim(s) are stale and did not block this one")
    if found:
        info(
            "The ledger now holds two live owners of the same path. Stand one of them down "
            "and release it — `tools claim_guard release --session <id>` — rather than "
            "deciding this by hand at the end."
        )
        return 1
    ok(f"{args.session} {action} {len(wanted)} path(s); the ledger has no overlapping live claim")
    return 0


def _run_release(args: argparse.Namespace) -> int:
    path = Path(args.ledger) if getattr(args, "ledger", None) else CLAIMS_PATH
    claims = read_claims(path)
    index = next((i for i, claim in enumerate(claims) if claim.session == args.session), None)
    if index is None:
        raise ToolError(f"no claim recorded for session {args.session!r}")
    released = set(_arg_paths(args.paths))
    held = claims[index].paths
    # No `--paths` means RELEASE EVERY PATH this session holds, which is the whole point
    # of standing a session down: an empty claim is not a record of anything, and keeping
    # the line would leave the next agent unable to claim the same work.
    keep = tuple(path for path in held if path not in released) if released else ()
    if keep:
        claims[index] = Claim(session=args.session, paths=keep, heartbeat=_now())
    else:
        # No path and no history: the line is deleted rather than parked as an empty
        # claim, because an empty claim is not a record of anything and every future run
        # would carry it. INC-0023's whole mechanism is a claim that outlived its session.
        del claims[index]
    write_claims(claims, path)
    ok(f"{args.session} released {len(held) - len(keep)} path(s)")
    return 0


def _run_report(args: argparse.Namespace) -> int:
    path = Path(args.ledger) if getattr(args, "ledger", None) else CLAIMS_PATH
    now = _now()
    claims = read_claims(path)
    if not claims:
        info(f"no live claim recorded in {path.name}")
        return 0
    live, stale = split_stale(claims, now)
    for claim in sorted(live, key=lambda c: c.session):
        info(_describe_claim(claim, now))
    for claim in sorted(stale, key=lambda c: c.session):
        warn(_describe_claim(claim, now) + "   STALE, not counted")
    return 0


def run(args: argparse.Namespace) -> int:
    action = args.claim_action
    if action == "check":
        return _run_check(args)
    if action == "claim":
        return _run_claim(args)
    if action == "release":
        return _run_release(args)
    if action == "report":
        return _run_report(args)
    raise ToolError(f"unknown claim_guard action: {action}")


if __name__ == "__main__":  # pragma: no cover - the dispatcher owns this
    print("run me as: uv run python -m tools claim_guard check", file=sys.stderr)
