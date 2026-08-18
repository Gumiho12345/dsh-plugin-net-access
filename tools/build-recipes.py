#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build-recipes.py — derive anchor-based patch recipes for dsh-plugin-net-access.

Method A: the installer no longer pins exact byte hashes per DSH version. Instead
manifest.json carries, for every patched file, a list of STRUCTURAL steps
(insert-before-anchor / exact replace) plus verification markers. install.ps1
applies those steps to whatever DSH version is installed; anchors that survive a
version bump need no recipe change, and a missing anchor aborts with a clear
message instead of corrupting the engine.

This script rebuilds recipes.json-equivalent content (written to manifest.json)
from a pristine engine tree and the shipped reference patches:

    python tools/build-recipes.py --pristine <engine-root> [--write]

The pristine root is a node_modules/@deepseek-ai tree; for every target the
pristine file is taken from <root>/<file>.netaccess.bak (install.ps1 backups)
falling back to <root>/<file>. The patched side is patches/<file> in this repo.

Steps are derived with difflib so whitespace (tabs) is taken verbatim from the
real files. Anchors are extended until unique in the pristine file. A final
verification re-applies the steps to the pristine text and requires byte-equal
output vs the shipped patch — any drift fails the run.

--write updates manifest.json in place (version/note kept, recipes replaced).
"""
import argparse
import difflib
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
PATCHES = REPO / "patches"
MANIFEST = REPO / "manifest.json"

TARGETS = [
    "dsh-sandbox-policy/lib/index.js",
    "dsh-sandbox/lib/index.js",
    "dsh-permission-presets/lib/index.js",
    "dsh-sandbox-windows-acl/lib/runner.js",
    "dsh-sandbox-windows-acl/lib/types-CNjZgO4h.js",
    "dsh-sandbox-local/lib/index.js",
    "dsh-tool-pwsh/lib/index.js",
    "dsh-client-connection/lib/client.js",
    "dsh-client-ui-conversation/lib/client.js",
]

# Marker overrides: default marker is "net-access"; files whose net-access
# strings might be absent/varied get a stronger unique marker.
MARKER_OVERRIDES = {
    "dsh-sandbox-windows-acl/lib/runner.js": ["DSH_NETACCESS_TOOLBIN"],
}


def read_text(path):
    return path.read_bytes().decode("utf-8")


def apply_steps(text, steps):
    """Apply recipe steps to `text` (line-based, exact). Raises RecipeError."""
    lines = text.split("\n")
    for step in steps:
        if step["type"] == "insert":
            anchor_lines = step["before"].split("\n")
            hits = [
                i
                for i in range(len(lines) - len(anchor_lines) + 1)
                if lines[i : i + len(anchor_lines)] == anchor_lines
            ]
            if len(hits) != 1:
                raise RecipeError(
                    f"insert anchor {'missing' if not hits else f'ambiguous ({len(hits)} hits)'}: {step['before'][:80]!r}"
                )
            lines[hits[0] : hits[0]] = step["lines"].split("\n")
        elif step["type"] == "replace":
            frm = step["from"].split("\n")
            to = step["to"].split("\n")
            hits = [
                i
                for i in range(len(lines) - len(frm) + 1)
                if lines[i : i + len(frm)] == frm
            ]
            if len(hits) != 1:
                raise RecipeError(
                    f"replace target {'missing' if not hits else f'ambiguous ({len(hits)} hits)'}: {step['from'][:80]!r}"
                )
            lines[hits[0] : hits[0] + len(frm)] = to
        else:
            raise RecipeError(f"unknown step type: {step['type']}")
    return "\n".join(lines)


class RecipeError(Exception):
    pass


def unique_anchor_starting_at(lines, idx, max_extend=6):
    """Return a line block starting at lines[idx] that occurs exactly once in `lines`."""
    for k in range(0, max_extend + 1):
        end = idx + k
        if end >= len(lines):
            break
        block = lines[idx : end + 1]
        cnt = sum(
            1
            for i in range(len(lines) - k)
            if lines[i : i + k + 1] == block
        )
        if cnt == 1:
            return "\n".join(block)
    raise RecipeError(f"cannot find unique anchor starting at line {idx + 1}")


def derive_steps(pristine_lines, patched_lines):
    sm = difflib.SequenceMatcher(a=pristine_lines, b=patched_lines, autojunk=False)
    steps = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        if tag == "delete":
            raise RecipeError("patch contains a deletion; recipes only support insert/replace")
        if tag == "insert":
            if i1 >= len(pristine_lines):
                raise RecipeError("insert at end of file is unsupported")
            anchor = unique_anchor_starting_at(pristine_lines, i1)
            steps.append({"type": "insert", "before": anchor, "lines": "\n".join(patched_lines[j1:j2])})
        elif tag == "replace":
            frm = "\n".join(pristine_lines[i1:i2])
            to = "\n".join(patched_lines[j1:j2])
            steps.append({"type": "replace", "from": frm, "to": to})
    return steps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pristine", required=True, help="engine root (node_modules/@deepseek-ai) with .netaccess.bak files")
    ap.add_argument("--write", action="store_true", help="write updated recipes into manifest.json")
    args = ap.parse_args()

    root = pathlib.Path(args.pristine)
    recipes = []
    problems = []

    for file in TARGETS:
        pristine_path = root / (file + ".netaccess.bak")
        if not pristine_path.exists():
            pristine_path = root / file
        patched_path = PATCHES / file
        if not pristine_path.exists() or not patched_path.exists():
            problems.append(f"missing files for {file}")
            continue
        pristine_text = read_text(pristine_path)
        patched_text = read_text(patched_path)
        # normalize CRLF just in case the source checkout is CRLF-mangled
        pristine_text = pristine_text.replace("\r\n", "\n")
        patched_text = patched_text.replace("\r\n", "\n")

        steps = derive_steps(pristine_text.split("\n"), patched_text.split("\n"))
        markers = MARKER_OVERRIDES.get(file, ["net-access"])

        # verification: apply steps to pristine, must equal patched byte-for-byte
        try:
            rebuilt = apply_steps(pristine_text, steps)
        except RecipeError as e:
            problems.append(f"{file}: cannot apply derived steps: {e}")
            continue
        if rebuilt != patched_text:
            problems.append(f"{file}: rebuilt patch != shipped patch (recipe drift)")
            continue
        for m in markers:
            if m not in rebuilt:
                problems.append(f"{file}: marker {m!r} missing after rebuild")
                continue

        recipes.append({"file": file, "steps": steps, "markers": markers})
        print(f"OK  {file}: {len(steps)} step(s)")

    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  " + p)
        sys.exit(1)

    if args.write:
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        data["recipes"] = recipes
        # drop legacy hash keys if present
        if "targets" in data:
            del data["targets"]
        MANIFEST.write_text(json.dumps(data, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
        print(f"\nmanifest.json updated: {len(recipes)} recipes")
    else:
        print(f"\n{len(recipes)} recipes derived OK (no --write, manifest untouched)")


if __name__ == "__main__":
    main()
