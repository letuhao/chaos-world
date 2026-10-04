"""Locate and invoke the Godot 4.7.x binary."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from collections.abc import Iterator
from contextlib import contextmanager, suppress
from datetime import UTC, datetime, timedelta
from pathlib import Path

from .common import REPO_ROOT, ToolError, info, warn

CONFIG_FILE = REPO_ROOT / ".godot-bin"
BUILD_DIR = REPO_ROOT / "build"

# Godot's own log file is a disk hazard, not a convenience. By default it writes
# to %APPDATA%/Godot/app_userdata/<project>/logs/, rotating at 2 GB per file with
# no total ceiling and max_log_files=5 — so a run that spins printing errors (a
# broken test looping on a guard it does not own) writes ~10 GB before anyone
# notices, and does it again on the next run. `debug/file_logging/enable_file_logging`
# in project.godot does NOT stop it: the engine reads the `.pc` variant, which
# stays true. Only the `--log-file` CLI flag redirects the sink, so every
# invocation goes through here and points the log at a scratch file the caller
# may delete, instead of the user's roaming profile.
#
# One file PER RUN, not one shared path. A single shared path is wrong twice over
# under the concurrency this repo actually runs in: concurrent runs interleave
# into the same file, so the byte ceiling below sums every writer at once and
# kills an innocent run because a *different* run is spinning, and the tail that
# would diagnose it is overwritten before anyone reads it. The diagnostic trail is
# the whole point of restoring logging, so each run gets its own file and the
# stale ones are swept.
LOG_DIR = BUILD_DIR / "logs"

# Where `user://` resolves for every run this launcher starts.
#
# `user://` follows the OS roaming profile, so without this the game's save lives
# at %APPDATA%/Godot/app_userdata/<project>/ and is SHARED by every task that boots
# the app (tools boot, tools run, tools ui) and by every run before it. The app
# restores from it when present (ItemWorkbenchApp._ready -> restore_actor), so a
# gate run's starting bag, equipment and outstanding loot were whatever the last
# run left behind. A gate whose verdict depends on untracked state outside the repo
# is not reproducible - BL-0743.
#
# There is deliberately NO `--user-data-dir` flag here: Godot 4.7 has no such
# option, and its CLI reference warns that "unknown command line arguments have no
# effect whatsoever", so passing one would look applied and relocate nothing.
# The environment is the lever that exists. On Windows `user://` derives from
# %APPDATA%; elsewhere it derives from the XDG data dir.
USER_DATA_DIR = BUILD_DIR / "godot-user"


def hermetic_env() -> dict[str, str]:
    """The child environment, with `user://` redirected inside the gitignored tree."""
    USER_DATA_DIR.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    if os.name == "nt":
        env["APPDATA"] = str(USER_DATA_DIR)
    else:
        env["XDG_DATA_HOME"] = str(USER_DATA_DIR)
    return env


# Distinguishes runs that share a PID and a wall-clock second. Not theoretical:
# `tools test` invokes the engine twice in one process (the import step, then the
# suite), and a warm-cache import can finish inside the same second the suite
# starts. A timestamp alone hands both runs the same sink and reinstates exactly
# the clobbering this scheme exists to prevent.
_RUN_SEQ = 0


def log_file_for(tag: str = "") -> Path:
    """A unique log path for one run, so concurrent runs cannot share a sink.

    `tag` names the caller (usually the suite filter) purely so a human reading
    `build/logs/` can tell which run wrote what; it is never the uniqueness.

    Uniqueness is pid + counter. A clock alone is NOT enough, and that was not
    hypothetical: `test` runs `--import` and then the suite, so a fast-failing
    import step and the suite that follows it start inside the same second and
    the second would have inherited the first one's file — precisely the
    clobbering this refactor exists to remove.
    """
    global _RUN_SEQ
    _RUN_SEQ += 1
    safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in tag)[:40]
    stamp = time.strftime("%H%M%S")
    name = f"{stamp}-{os.getpid()}-{_RUN_SEQ}-{safe or 'run'}.log"
    return LOG_DIR / name


# Old logs are swept so the scratch trail cannot itself become the hazard it was
# built to prevent. Kept several deep: a failing run's tail is worth having until
# someone has actually read it.
LOG_RETENTION = 8


# A test that cannot make progress must fail loudly and quickly. Without a
# ceiling, a non-terminating loop or a runaway assert-spiral runs until someone
# notices the machine is hot — which is the failure mode this whole module
# exists to prevent. Kept generous: the full suite legitimately takes minutes.
TIMEOUT_SECONDS = 900

# Resident memory ceiling, in bytes. The clock and the disk ceilings both measure
# OUTPUT, so a run that allocates without printing sails past both: observed as a
# tests/ui run reaching 67 GB resident and 105 GB commit at ~0.3 GB/s while a
# healthy run peaks near 120 MB, which on a 96 GB machine means the OS starts
# paging and the desktop stops responding — the user has to power off to get it
# back. This is the same hazard the log ceiling addresses, one resource over.
#
# A test leaking a Node or a String every iteration burns RAM exactly the way a
# loop that spams burns disk, and it is just as invisible: nothing is printed.
RAM_CEILING_BYTES = 12 * 1024 * 1024 * 1024
# Godot's own baseline under this project is tens of MB, so a generous ceiling
# costs nothing on a healthy run and still fires long before the machine swaps.

# One engine at a time may touch a given project directory. Godot writes the
# shared import cache (`game/.godot/`) on every `--import`, and several agents
# running `tools test` concurrently interleave writes to it, which shows up as a
# suite that dies during startup with no output rather than as an honest error.
# The lock is a real filesystem lock, not a polite convention: it is held by the
# OS for the life of the child, so a crashed run releases it automatically.
#
# Bounded, and it FAILS rather than waiting forever. A stale lock that never
# releases is the disk-hazard pattern this module exists to prevent, so the
# ceiling here is generous but finite and the failure is a readable error.
#
# Sized for the fleet this repo actually runs under. Several agents can queue
# behind one another and each full suite legitimately takes minutes, so a short
# ceiling expires while merely waiting for a turn and reports a misleading
# failure. Matches TIMEOUT_SECONDS: long enough to queue, bounded enough that a
# genuinely wedged lock surfaces quickly.
PROJECT_LOCK = LOG_DIR / "godot.lock"
LOCK_WAIT_SECONDS = 900

# WHO holds the lock, published beside it. INC-0018: the expiry error used to say only
# "held for more than 900s", so "queued behind a live run" and "held by a process that
# died mid-lock" were the same sentence. With ~20 agents the first is routine and the
# second is a genuine incident, and the only safe response to an ambiguous lock is to
# WAIT - so an agent that cannot tell them apart eventually deletes the lock file, which
# is BL-0424 on a lock with a live owner and lets two Godot processes write one project.
#
# The sidecar is what tells them apart. It is written on ACQUIRE and removed on RELEASE,
# and the OS drops the advisory lock the instant the holder's process dies without
# running that `finally`. So the sidecar's ABSENCE while someone is demonstrably blocked
# is itself the finding: it can only mean the previous owner died holding the lock. That
# possibility is reported, not hidden - see `_lock_expiry`.
#
# Two things this sidecar is deliberately NOT:
#
#   - Not mtime. `godot.lock`'s own mtime is worthless here (the incident reporter found
#     it 22 hours old and empty, which looks exactly like a stale lock, while it was
#     live: an OS advisory lock ignores mtime entirely). This file's own mtime is equally
#     suspect for the same reason - it records when the holder was last *touched*, not
#     how long it has held. The explicit `since` field is authoritative; `stat` is only
#     ever a fallback for a sidecar too malformed to parse.
#   - Not a liveness oracle. A stale sidecar in a moment when the lock is FREE says
#     nothing about a current holder, and is the residue of an acquisition whose owner
#     was killed between taking the lock and writing this file. The consumer therefore
#     only reads it where a failed `msvcrt.locking`/`fcntl.flock` has just PROVED
#     somebody else holds the lock, which is what makes the sidecar meaningful at all.
PROJECT_LOCK_OWNER = LOG_DIR / "godot.lock.owner"

# Both locking backends below take an EXCLUSIVE byte-range lock held by the operating
# system for the life of the process (Windows: `msvcrt.locking`, POSIX: `fcntl.flock`).
# A handle close does NOT release it, which is why the finally below explicitly unlocks:
# on the docstring's account `handle.close()` is "the last reference the lock file has
# outside this process", which is not the same claim as "this releases the lock". So the
# unlock has to run, and a process that dies without running it relies on the OS instead.
#
# That last step is the one this whole change turns on, and it is worth being exact
# about it: the repo cannot verify it. `msvcrt.locking` is a thin wrapper over
# `LockFile`/`LockFileEx`, and whether the byte range is dropped when a process dies
# belongs to the kernel - as does whether the calling process is a lock OWNER or a lock
# HANDLE holder (Windows terminology, not the POSIX one). Neither is decided by anything
# in this file, and nothing here tests it. What IS true and is relied on:
#
#   - The next acquirer's non-blocking lock attempt returned `OSError` *just now*. That
#     is observed, not assumed, and it is the entire premise of every claim below. If
#     someone is holding it, they are holding it.
#   - The holder has not released it. The holder's own release is the `finally` block
#     below; the holder that is *not* releasing it is a process that is not executing
#     that block, i.e. one that was killed or crashed.
#
# Those two together are the whole of "safe to proceed": no process of ours is in the
# critical section, and the sidecar says whose it was. The claim is deliberately NOT
# "this file is stale", because that is the claim INC-0018 says is unverifiable, and it
# is not what is being asserted.


@contextmanager
def project_lock() -> Iterator[None]:
    """Hold an exclusive lock on the Godot project directory.

    Serialises `--import` and suite runs so concurrent agents cannot corrupt the
    shared import cache. Fails loudly after `LOCK_WAIT_SECONDS` rather than
    blocking indefinitely, and the failure names the holder.

    Publishes `PROJECT_LOCK_OWNER` for the life of the critical section and removes it
    on the way out, so a blocked agent can tell a live queue from a lock whose owner
    died without running the cleanup. Nothing here ever deletes `PROJECT_LOCK` itself:
    the advisory lock IS the mutual exclusion, so unlinking it would hand the next
    arriving process a file nobody holds a lock on.
    """
    PROJECT_LOCK.parent.mkdir(parents=True, exist_ok=True)
    handle = open(PROJECT_LOCK, "a+")  # noqa: SIM115 - closed in the finally below
    acquired = False
    deadline = time.monotonic() + LOCK_WAIT_SECONDS
    try:
        while not acquired:
            try:
                if os.name == "nt":
                    import msvcrt

                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl

                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                acquired = True
            except OSError:
                if time.monotonic() >= deadline:
                    raise ToolError(
                        _lock_expiry(
                            f"another Godot run still held {PROJECT_LOCK.name} after "
                            f"{LOCK_WAIT_SECONDS}s; giving up rather than waiting forever"
                        )
                    ) from None
                time.sleep(1.0)
        # Only written once the lock is HELD, so the sidecar can never claim a holder
        # that does not have it. The gap between the line above and this write is the
        # only window where the sidecar can be absent for a live holder: a process
        # killed inside it takes the lock with it. That is a microsecond, and it is the
        # same by construction on every release, so it is far from the 900s that
        # distinguishes the two readings.
        _write_lock_owner()
        yield
    finally:
        # Clear the sidecar BEFORE unlocking. The other order has a real failure mode:
        # between the unlock and the unlink another agent can legitimately acquire the
        # lock and write its own sidecar, and this process would then delete it - leaving
        # a live lock with no owner record, which reads as the dead-holder case and is
        # exactly the confusion this file exists to remove.
        _clear_lock_owner()
        if acquired:
            try:
                if os.name == "nt":
                    import msvcrt

                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    import fcntl

                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
            except OSError as exc:  # pragma: no cover - best-effort release
                warn(f"could not release the project lock: {exc}")
        handle.close()


def _utc_now() -> datetime:
    """Now, in the timezone the sidecar records - UTC, so two machines on two zones
    still write a comparable `since`."""
    return datetime.now(UTC)


def _write_lock_owner() -> None:
    """Publish who holds the lock and since when, for a blocked agent to read.

    Written atomically: a reader can find a truncated sidecar if the write were not,
    and a half-written record is indistinguishable from a corrupted one.

    Best-effort by design. It is a diagnostic, and refusing to run Godot because a
    diagnostic could not be written would turn a reporting nicety into the outage. The
    expiry path degrades honestly: an unreadable sidecar is reported as unreadable
    rather than guessed at.
    """
    moment = _utc_now()
    record = json.dumps(
        {
            "pid": os.getpid(),
            "since": moment.isoformat(timespec="seconds"),
            "lock": PROJECT_LOCK.name,
        }
    )
    staging = PROJECT_LOCK_OWNER.with_name(PROJECT_LOCK_OWNER.name + f".{os.getpid()}")
    try:
        staging.write_text(record + "\n", encoding="utf-8")
        os.replace(staging, PROJECT_LOCK_OWNER)
    except OSError as exc:
        warn(f"could not record the lock holder in {PROJECT_LOCK_OWNER.name}: {exc}")
        with suppress(OSError):
            staging.unlink()


def _clear_lock_owner() -> None:
    """Remove the sidecar this process wrote, and never anyone else's.

    The `pid` guard is the whole point. A process killed between acquiring the lock and
    writing the sidecar leaves none, so that is not a source of a survivor; but a
    process killed *during* a run leaves one, and the next holder must not remove it on
    the strength of reaching its own `finally` - the sidecar is the evidence that the
    dead owner never reached theirs. So the record that is deleted has to be provably
    ours.
    """
    try:
        record = json.loads(PROJECT_LOCK_OWNER.read_text(encoding="utf-8"))
        mine = record.get("pid") == os.getpid()
    except (OSError, ValueError):
        mine = False
    if not mine:
        return
    with suppress(OSError):
        PROJECT_LOCK_OWNER.unlink()


def _held_since(since: str) -> str:
    """How long the lock has been held, in human units.

    Minutes once it matters, seconds while the numbers are still small - the difference
    between "12s" and "12m" is the difference between a run that just started and one
    that has been stuck for a fifth of the wait ceiling, and only the second one is
    worth interrupting anyone over.

    An unparseable timestamp is reported as such rather than guessed at: an age
    computed from a fallback would be a number nobody can act on.
    """
    try:
        age = _utc_now() - datetime.fromisoformat(since)
    except (TypeError, ValueError):
        return "an unknown time (the recorded `since` is not a readable timestamp)"
    if age < timedelta(minutes=1):
        return f"{int(age.total_seconds())}s"
    return f"{int(age.total_seconds() // 60)}m"


def _lock_expiry(lede: str) -> str:
    """Name the holder on an expired wait, or say plainly that nobody has.

    The two cases this separates are the ones INC-0018 says looked identical. Reaching
    here means a non-blocking lock attempt failed, so somebody does hold the lock; the
    only question is whether they are alive and running Godot.

    The next action is named in both branches, and they are opposite:

      - A sidecar exists, so the holder published an identity. WAIT. It may be queued
        work rather than a stuck run, and the only safe response to a live holder is
        patience.
      - No sidecar exists, so the holder published nothing. Re-run and it will acquire.
        Waiting cannot help, because the process this error is about is not running.

    The second branch is a conclusion drawn from a negative, so it says exactly how far
    the evidence goes rather than asserting a fact about the kernel: the lock attempt
    really did fail (observed), the holder never published an identity (observed), and
    the holder is therefore a process that did not reach its cleanup - killed, crashed,
    or stopped between acquiring the lock and writing its sidecar. Whether the OS has
    already dropped its advisory lock is the one step this module cannot verify from
    inside Python, and the instruction is written to be correct under either answer:
    prove it by re-running, rather than asserting it. Re-running is safe in both cases
    because the lock is mutual exclusion, not a flag - if the previous owner really is
    still alive, the re-run simply queues behind it again, which is what waiting would
    have done.

    It never says "delete the lock file", and neither should anything else. The file is
    the mutual exclusion; removing it lets two Godot processes write one project
    (BL-0424).
    """
    try:
        record = json.loads(PROJECT_LOCK_OWNER.read_text(encoding="utf-8"))
        pid, since = record["pid"], record["since"]
    except FileNotFoundError:
        pid = since = None
    except (OSError, ValueError, KeyError, TypeError):
        pid, since = None, None
    head = f"{lede}. {PROJECT_LOCK_OWNER.name} says: "
    if pid is None:
        return (
            head + "no holder has ever recorded itself there. Nobody alive is holding "
            "this lock through this tool - the process that took it was killed, crashed, "
            "or stopped before it could write its own sidecar, which is exactly the "
            "case the old message could not express. WAITING CANNOT HELP: that process "
            "is not running to release anything. Next action: re-run the same command. "
            "There is no need to touch " + PROJECT_LOCK.name + " - the file is the "
            "mutual exclusion, and removing it is how two Godot processes end up "
            "writing one project (BL-0424). If the re-run fails to acquire with this "
            "same message, then some holder really is still in the critical section "
            "and this diagnosis is wrong: report that, do not delete the file."
        )
    return (
        f"{head}pid {pid}, holding it since {since} - {_held_since(since)} as of "
        f"now, so this is a live queue, not a dead holder. Next action: WAIT, and do "
        f"engine-free work meanwhile (tools guards, tracker writes, ADRs, static "
        f"checks, gdformat/gdlint --check; none of them take the lock). Do not delete "
        f"{PROJECT_LOCK.name}: it is the mutual exclusion, and it ignores mtime, so a "
        f"22-hour-old empty lock file is NOT evidence of a stale one - that reading is "
        f"what nearly cost this repo BL-0424 on a live owner. If pid {pid} is not in "
        f"`tasklist`, its holder has died without releasing, and the next run takes the "
        f"lock on its own; waiting is then simply a waste of the ceiling."
    )


# A wall-clock ceiling bounds TIME, not BYTES, and that gap cost 10 GB of an SSD
# in practice. A `while` retrying an unreachable exit condition at the measured
# ~1 GB/s would be allowed to write ~900 GB inside TIMEOUT_SECONDS — far past a
# whole disk. The clock cannot catch a fast writer, so the log's size is watched
# directly and the run is killed the moment it goes pathological. Sized well above
# any honest run (a normal full suite logs well under a megabyte) while staying
# harmless: it is a ceiling on garbage, not a budget for work.
LOG_BYTE_CEILING = 64 * 1024 * 1024

# Measured, and the measurement is the reason for this constant: the guard's
# detection granularity IS the overshoot. A re-measured flooder sustains ~2 GB/s
# (a 1 MB write loop was killed at 0.12s having written 251 MB), so at 20 Hz the
# overshoot lands around 100 MB rather than the 50 MB an earlier, slower
# measurement suggested. Detection can never precede the breach, only approach
# it, so tightening the ceiling buys nothing — only the interval does. 20 stat()
# calls a second costs nothing next to a Godot run; see BL-0239.
LOG_POLL_SECONDS = 0.05

# A run that has produced NO output for this long is stuck, not starting up. It
# exists because the byte ceiling and the wall clock both measure output, so a
# silent hang defeats both (BL-0242): it costs no disk but burns the whole
# 900 s budget and leaves no trail. Sized to clear the slowest real startup
# measured here — the `--import` pass that precedes a suite run — with room to
# spare, so it fires on a hang rather than on a cold, slow start.
SILENCE_GRACE_SECONDS = 120

# When each child was launched, keyed by pid, so `_silent_breach` can measure
# silence from the right instant. `Popen` records no start time of its own.
_STARTED: dict[int, float] = {}


## The three lines below, verbatim, as a self-test fixture. `tools/godot_bypass.py` exempts
## THIS file from the rules that catch `.godot-bin`, `GODOT_BIN` and a PATH search for
## `godot`/`godot4` — reading them is this module's job, and it is the only thing every
## other rule there routes toward. Exempting a file by path is a hole in a guard, so
## `tools selftest run` asserts the exemption still holds (INC-0016): a guard that has been
## narrowed to nothing and a guard that fires on the resolver are equally broken, and only
## the pair of cases separates them.
GODOT_BYPASS_EXEMPT_PROBE = (
    'CONFIG_FILE = REPO_ROOT / ".godot-bin"\n'
    '    env = os.environ.get("GODOT_BIN")\n'
    '    found = shutil.which("godot") or shutil.which("godot4")\n'
)


def find_godot() -> str:
    """Resolve Godot from GODOT_BIN, the local .godot-bin file, or PATH; fail loudly."""
    env = os.environ.get("GODOT_BIN")
    if env:
        path = Path(env)
        if path.is_file():
            return str(path)
        raise ToolError(f"GODOT_BIN points to a missing file: {env}")
    if CONFIG_FILE.is_file():
        configured = CONFIG_FILE.read_text(encoding="utf-8").strip()
        if configured:
            path = Path(configured)
            if path.is_file():
                return str(path)
            raise ToolError(f".godot-bin points to a missing file: {configured}")
    found = shutil.which("godot") or shutil.which("godot4")
    if found:
        return found
    raise ToolError(
        "Godot binary not found. Set GODOT_BIN or write its path to .godot-bin "
        "(a Godot 4.7.x executable)."
    )


def run_godot(
    args: list[str],
    capture: bool = False,
    timeout: int | None = None,
    tag: str = "",
) -> subprocess.CompletedProcess:
    """Invoke Godot with the disk-writing log redirected and both ceilings enforced.

    Raises ToolError on either ceiling. The child is killed, not merely abandoned,
    so a spinning engine cannot keep writing to its log after the tool gives up.

    Serialised against other runs through `project_lock`, because every Godot
    invocation writes the shared import cache under `game/.godot/`.
    """
    with project_lock():
        return _run_godot_locked(args, capture, timeout, tag)


def _run_godot_locked(
    args: list[str],
    capture: bool,
    timeout: int | None,
    tag: str,
) -> subprocess.CompletedProcess:
    cmd = [find_godot(), *args]
    log_file = log_file_for(tag)
    log_file.parent.mkdir(parents=True, exist_ok=True)
    # Keep the sink inside the gitignored build/ tree; never the user profile.
    # It must go BEFORE any bare `--`: everything after that separator belongs to
    # the project, not the engine, so a trailing --log-file is silently ignored
    # and the run falls back to writing gigabytes into the user profile.
    separator = cmd.index("--") if "--" in cmd else len(cmd)
    cmd[separator:separator] = ["--log-file", str(log_file)]
    info("$ " + " ".join(cmd))
    limit = TIMEOUT_SECONDS if timeout is None else timeout
    sweep_old_logs()
    # Captured output goes to a FILE, never a PIPE. A pipe would deadlock: the
    # wait loop below blocks in proc.wait() while the child blocks writing to a
    # full pipe buffer, and neither can make progress until the other does. That
    # presented as a suite that produced no output at all and never finished,
    # which is indistinguishable from a hang in the code under test. A file has
    # no capacity limit, so the child always completes and the guard stays in
    # charge of killing genuinely stuck runs.
    out_file = err_file = None
    if capture:
        out_file = log_file.with_suffix(".out")
        err_file = log_file.with_suffix(".err")
    try:
        stream_out = open(out_file, "w", encoding="utf-8", errors="replace") if capture else None
        stream_err = open(err_file, "w", encoding="utf-8", errors="replace") if capture else None
    except OSError as exc:
        raise ToolError(f"could not open capture files: {exc}") from None
    try:
        proc = subprocess.Popen(
            cmd,
            text=True,
            stdout=stream_out,
            stderr=stream_err,
            env=hermetic_env(),
        )
    except OSError as exc:
        if stream_out:
            stream_out.close()
        if stream_err:
            stream_err.close()
        raise ToolError(f"could not start Godot: {exc}") from None
    _STARTED[proc.pid] = time.monotonic()
    try:
        _guard_until_done(proc, limit, log_file, out_file, err_file)
    finally:
        # Close the parents' copies so the files are flushed and no handle is
        # left holding them on Windows.
        if stream_out:
            stream_out.close()
        if stream_err:
            stream_err.close()
    return subprocess.CompletedProcess(
        cmd,
        proc.returncode,
        _read_capture(out_file),
        _read_capture(err_file),
    )


def sweep_old_logs() -> None:
    """Drop the oldest run logs once there are more than `LOG_RETENTION`.

    Counting, not age: a fresh log is created before this runs, so an
    age-based rule would delete a concurrent run's in-progress log, and a
    keep-count would keep them forever. Only whole-file unlink of the oldest is
    attempted, and a file still held open by a live run is simply skipped — the
    OS refuses it, which is the correct answer.
    """
    # Every sink a run produces, not just the engine log. Sweeping `*.log` alone
    # left the `.out`/`.err` capture files behind forever, because those are the
    # ones a captured run actually fills — observed as 1278 orphaned `.err` and
    # 1278 `.out` files totalling ~90 MB while only 9 `.log` files survived.
    # Retention counts files, so a run that produces three is kept as three.
    logs = sorted(_run_sinks_all(), key=lambda p: p.stat().st_mtime)
    for stale in logs[: max(0, len(logs) - LOG_RETENTION * 3)]:
        try:
            stale.unlink()
        except OSError:
            continue


def _run_sinks_all() -> list[Path]:
    """Every output file this tool writes, in any of the three sink shapes."""
    return [path for pattern in ("*.log", "*.out", "*.err") for path in LOG_DIR.glob(pattern)]


def _guard_until_done(
    proc: subprocess.Popen,
    limit: int,
    log_file: Path,
    out_file: Path | None,
    err_file: Path | None,
) -> tuple[str | None, str | None]:
    """Wait for the engine, killing it if it overruns the clock OR the disk budget.

    Two independent ceilings, because they catch different failures: the clock
    catches a slow loop, the byte ceiling catches a fast one. The fast one is the
    case that actually costs gigabytes before anyone notices, and it is the case a
    wall-clock ceiling cannot see.

    Capture is read from files after the child exits, never from pipes: `wait()`
    and a pipe that nobody drains deadlock against each other, which reads from
    outside as a suite that silently produces nothing.
    """
    deadline = time.monotonic() + limit
    try:
        while True:
            # Check BEFORE waiting, so a writer that is already past the ceiling is
            # caught on the first pass instead of after a full poll interval.
            breach = _breach(proc, deadline, limit, log_file)
            if breach is not None:
                # Kill explicitly rather than abandoning the child: a Godot that
                # spawned a console pair can outlive its parent and keep writing.
                proc.kill()
                proc.wait()
                _kill_stray_godot(proc.pid)
                raise ToolError(breach + " Re-run with --suite <substring> to isolate it.")
            silent = _silent_breach(log_file, limit, proc)
            if silent is not None:
                proc.kill()
                proc.wait()
                _kill_stray_godot(proc.pid)
                raise ToolError(silent)
            try:
                proc.wait(timeout=LOG_POLL_SECONDS)
                break
            except subprocess.TimeoutExpired:
                pass
    finally:
        # The child owns its own handles now; releasing ours is what lets the
        # next sweep delete these files. The start time goes too: a long tool
        # run launches many Godots, and an entry per dead pid would grow forever.
        _STARTED.pop(proc.pid, None)
        for stream in (proc.stdout, proc.stderr):
            if stream is not None:
                stream.close()
    if out_file is None or err_file is None:
        return None, None
    return _read_capture(out_file), _read_capture(err_file)


def _read_capture(path: Path | None) -> str | None:
    """Captured output, or None when the run was not captured.

    A missing file is a normal outcome, not an error: the child can die before
    the engine opens its streams, and the log files carry the real diagnosis.

    `None` in, `None` out. `run_godot(capture=False)` never opens the streams, and
    this is the only honest answer for a run that was not captured — returning ""
    would present an uncaptured run as one that captured nothing and said so.
    """
    if path is None:
        return None
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _silent_breach(log_file: Path, limit: int, proc: subprocess.Popen) -> str | None:
    """Why a run that has written nothing at all must be killed, else None.

    The other two ceilings both measure OUTPUT, so a run that produces none slips
    past both: a silent hang costs no disk but costs the whole 900 s budget and
    leaves no trail to diagnose. That is the failure mode this closes (BL-0242).

    The grace is `SILENCE_GRACE_SECONDS`, not zero: a healthy run is not silent
    from its first millisecond — the engine prints its banner before it does any
    work — so killing on "no bytes yet" would fail every cold start. The grace
    therefore has to exceed the time a real run takes to say ANYTHING, which is
    the import pass that precedes the suite. It is a stall ceiling, not a speed
    budget: a run that has been alive this long and has said nothing is stuck.
    """
    if _log_size(log_file) > 0:
        return None
    if time.monotonic() - _started_at(proc) < SILENCE_GRACE_SECONDS:
        return None
    return (
        f"Godot wrote nothing at all to its log for {SILENCE_GRACE_SECONDS}s and was "
        f"killed. It is alive but silent: not a flood, so the byte ceiling cannot see "
        "it, and not slow enough to trip the clock within the budget. Treat it as a "
        "bug in the code under test — a script that blocks before its first print, a "
        "deadlock, or a load that never resolves. The log is at "
        f"{log_file}."
    )


def _started_at(proc: subprocess.Popen) -> float:
    """When the child started, in the same clock `_breach` uses.

    `Popen` does not record a start time, and reading the child's CPU time would
    be a different clock entirely. So the start is recorded by `run_godot` in a
    module-level map keyed by pid, which is also what lets this work for a run
    that never produces output at all — the one case where there is nothing else
    to measure.
    """
    return _STARTED.get(proc.pid, time.monotonic())


def _breach(
    proc: subprocess.Popen,
    deadline: float,
    limit: int,
    log_file: Path,
) -> str | None:
    """Why this run must be killed, or None while it is still within both ceilings.

    Checked BEFORE each wait so a writer already past the ceiling is caught on the
    first pass rather than after a full poll interval. The wall clock is checked
    first because a run that both hangs and floods is a hang, and the hang is the
    more actionable half of the diagnosis.
    """
    if time.monotonic() > deadline:
        return (
            f"Godot did not finish within {limit}s and was killed. This is a bug, "
            "not slowness: look for a loop that never terminates or an assertion "
            "inside one."
        )
    resident = _resident_bytes(proc.pid)
    if resident > RAM_CEILING_BYTES:
        return (
            f"Godot reached {resident // (1024 * 1024 * 1024)} GB resident and was "
            f"killed at the {RAM_CEILING_BYTES // (1024 * 1024 * 1024)} GB ceiling, "
            "without writing anything the other ceilings could see. A healthy run "
            "peaks near 120 MB, so this is memory that is never released: a test "
            "leaking a Node, a Resource or a String on every iteration of a loop. "
            "The loop is the bug — fix it, do not raise this ceiling. The tail is "
            f"in {log_file}."
        )
    written = _written_bytes(log_file)
    if written > LOG_BYTE_CEILING:
        return (
            f"Godot wrote {written // (1024 * 1024)} MB in under the time "
            f"limit and was killed at the {LOG_BYTE_CEILING // (1024 * 1024)} MB "
            "ceiling. A healthy run logs kilobytes, so that rate means a loop is "
            "spinning on an exit condition it can never satisfy — usually a `while` "
            f"retrying a verb the game refuses to accept. The tail is in {log_file}."
        )
    return None


def _resident_bytes(pid: int) -> int:
    """Resident working set of one process in bytes, or 0 if it cannot be read.

    Read through `GetProcessMemoryInfo` rather than by shelling out to
    PowerShell or `wmic`: this runs on every poll of a live run, so it has to be
    cheap, and spawning a shell per poll is itself a measurable cost on a machine
    already short of RAM — which is exactly when this check matters most.

    Working set, not commit: the hazard is physical memory the machine cannot
    spare, and that is what working set measures.
    """
    if os.name != "nt":
        return 0
    try:
        import ctypes
        from ctypes import wintypes
    except ImportError:  # pragma: no cover - ctypes is stdlib on every platform
        return 0

    class _Counters(ctypes.Structure):
        _fields_ = [
            ("cb", wintypes.DWORD),
            ("PageFaultCount", wintypes.DWORD),
            ("PeakWorkingSetSize", ctypes.c_size_t),
            ("WorkingSetSize", ctypes.c_size_t),
            ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
            ("QuotaPagedPoolUsage", ctypes.c_size_t),
            ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
            ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
            ("PagefileUsage", ctypes.c_size_t),
            ("PeakPagefileUsage", ctypes.c_size_t),
        ]

    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
    psapi = ctypes.windll.psapi  # type: ignore[attr-defined]

    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return 0
    try:
        counters = _Counters()
        counters.cb = ctypes.sizeof(_Counters)
        if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return 0
        return int(counters.WorkingSetSize)
    finally:
        kernel32.CloseHandle(handle)


def _written_bytes(log_file: Path) -> int:
    """Bytes this run has written across ALL of its sinks.

    The ceiling used to watch the `--log-file` sink alone, which missed the case
    that actually burns the disk: a run whose stdout/stderr are captured to files
    spins into its `.err` while the engine log stays empty, so nothing tripped.
    Observed: a single 31 MB `.err` beside a healthy-sized log, with the run
    still going. `push_error` writes to stderr, so a test looping on an assertion
    is precisely the shape that slips through.
    """
    return sum(_log_size(candidate) for candidate in _run_sinks(log_file))


def _run_sinks(log_file: Path) -> tuple[Path, ...]:
    """The engine log plus the capture files derived from it."""
    return (log_file, log_file.with_suffix(".out"), log_file.with_suffix(".err"))


def _log_size(log_file: Path) -> int:
    """Bytes in one of this run's output files, or 0 if it does not exist yet."""
    try:
        return log_file.stat().st_size
    except OSError:
        return 0


def _kill_stray_godot(pid: int) -> None:
    """Kill the engine process tree THIS run started, and nothing else.

    Scoped to one tree on purpose. The sweep used to be `taskkill /IM
    Godot*.exe`, which matches by image name and therefore killed every Godot on
    the machine: a concurrent agent's suite, and any interactive editor session.
    Under the concurrency this repo actually runs in that is not merely rude, it
    is a deadlock — a run that trips its ceiling killed its neighbours, each of
    which then tripped its own ceiling and killed back, so N concurrent runs kept
    resetting each other and none ever finished. Observed directly: 26 engines
    alive, under one second of CPU between them, no suite ever reporting.

    `/T` roots the kill at our own child, which is what actually needs cleaning
    up: Godot spawns a console/GUI pair and the child can outlive the parent the
    Popen handle is attached to.
    """
    try:
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(pid)],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        warn(f"could not sweep this run's Godot tree (pid {pid}): {exc}")


def clear_godot_log() -> None:
    """Remove every run log. Safe to call when there are none."""
    for path in LOG_DIR.glob("*.log"):
        try:
            path.unlink()
        except OSError:
            # A concurrent run still holding one open is expected and harmless.
            continue
