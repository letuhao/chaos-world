"""Translation tooling: inventory the player-facing strings, extract slugs, gate catalogs."""

from .engine import register, run

__all__ = ["register", "run"]
