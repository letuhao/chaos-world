"""Module boundary enforcement. Policy lives in `rules.py`, state in `registry.json`."""

from . import facade_constants, rules
from .enforce import register, run

# `facade_constants` is a guard in its own right with its own subcommand, so it
# is wired here rather than imported by `__main__` directly: one place decides
# what the arch package exposes.
register_facade_constants = facade_constants.register
run_facade_constants = facade_constants.run

__all__ = ["facade_constants", "register", "register_facade_constants", "rules", "run"]
