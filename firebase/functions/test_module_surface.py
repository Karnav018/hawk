"""Every name one backend module reaches for in another must exist.

A scripted edit once deleted `retrieval.search` and 290 tests stayed green:
nothing here called it, and `api.py` — which does — is never imported by a
test. The deploy went out and every `ask` failed with "module 'retrieval' has
no attribute 'search'" until the next one.

So this walks the *source* rather than trusting coverage. For each first-party
module a file imports, every `module.name` it reads and every
`from module import name` it pulls must be defined on that module.
"""

from __future__ import annotations

import ast
import importlib
from pathlib import Path

ROOT = Path(__file__).parent

#: First-party modules: top-level files and packages next to this test.
LOCAL = {p.stem for p in ROOT.glob("*.py")} | {
    p.name for p in ROOT.iterdir() if p.is_dir() and (p / "__init__.py").exists()
}


def _references() -> list[tuple[str, int, str, str]]:
    """(file, line, module, name) for every cross-module name in the source."""
    found: list[tuple[str, int, str, str]] = []
    for path in sorted(ROOT.glob("*.py")):
        if path.name.startswith("test_"):
            continue
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        aliases: dict[str, str] = {}
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name in LOCAL:
                        aliases[alias.asname or alias.name] = alias.name
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module in LOCAL:
                for alias in node.names:
                    if alias.name != "*":
                        found.append((path.name, node.lineno, node.module, alias.name))
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.Attribute)
                and isinstance(node.value, ast.Name)
                and node.value.id in aliases
            ):
                found.append((path.name, node.lineno, aliases[node.value.id], node.attr))
    return found


def test_every_cross_module_name_exists():
    references = _references()
    assert references, "the walk found nothing — is ROOT right?"

    modules: dict[str, object] = {}
    unimportable: dict[str, str] = {}
    missing: list[str] = []
    for file, line, module, name in references:
        if module not in modules and module not in unimportable:
            try:
                modules[module] = importlib.import_module(module)
            except Exception as error:  # reported below, not hidden
                unimportable[module] = f"{type(error).__name__}: {error}"
        if module in unimportable:
            continue
        if not hasattr(modules[module], name):
            missing.append(f"{file}:{line} reads {module}.{name}, which does not exist")

    assert not missing, "\n".join(missing)
    assert not unimportable, "\n".join(
        f"{module} could not be imported here: {why}" for module, why in unimportable.items()
    )
