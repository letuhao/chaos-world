"""Selftest registration for `arch.no_caller_verbs` (ADR 0188).

Kept in its own module because that is the pattern the harness already uses:
`selftest_cases.py` imports a cases module for its side effect and assigns it to
a name so ruff sees the import as used. Registering from inside
`no_caller_verbs.py` itself would put a `selftest` import inside the guard — a
cycle, since `selftest` is loaded by `__main__` before the guard's cases run.

Nothing here is a happy path. Every case asserts a RED verdict, because "the
guard passes on today's tree" is what `tools check` already does and proves
nothing (INC-0016).
"""

from __future__ import annotations

from ..selftest import case, expect, write
from .no_caller_verbs import register_selftest_cases

register_selftest_cases(case, expect, write)

__all__ = ["case", "expect", "register_selftest_cases", "write"]
