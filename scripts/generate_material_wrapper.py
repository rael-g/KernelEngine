#!/usr/bin/env python3
"""Emit one (material x pass) wrapper .slang from a pass template.

An authored material is only a `struct X : IMaterial` — it declares no entry
point and imports no pass, so it cannot be compiled on its own. Each consuming
pass ships a wrapper template (`<pass>_material.slang.in`) that knows how to
bind an IMaterial into that pass's entry points. This script pairs the two,
which is what makes the (material x pass) product a build-time artifact rather
than something a pass hardcodes.

The material's struct name is read from the source (the `: IMaterial`
conformance), not from a sidecar — a material declares what it is in one place.
"""

import argparse
import pathlib
import re
import sys

# `struct Foo : IMaterial {` — the conformance is the declaration of intent.
MATERIAL_STRUCT_RE = re.compile(
    r"^\s*struct\s+(\w+)\s*:\s*IMaterial\b", re.MULTILINE)


def find_material_struct(source: str, path: pathlib.Path) -> str:
    matches = MATERIAL_STRUCT_RE.findall(source)
    if not matches:
        sys.exit(f"{path}: no `struct <Name> : IMaterial` found — an authored "
                 f"material must declare its IMaterial conformance.")
    if len(matches) > 1:
        sys.exit(f"{path}: {len(matches)} IMaterial structs ({', '.join(matches)}) "
                 f"— one material per file, so the file name identifies it.")
    return matches[0]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--material", required=True, type=pathlib.Path,
                    help="authored material .slang (a lone `struct X : IMaterial`)")
    ap.add_argument("--template", required=True, type=pathlib.Path,
                    help="the consuming pass's wrapper template (.slang.in)")
    ap.add_argument("--output", required=True, type=pathlib.Path,
                    help="wrapper .slang to emit")
    args = ap.parse_args()

    material_src = args.material.read_text(encoding="utf-8")
    struct_name = find_material_struct(material_src, args.material)
    # Slang imports by module name; the module is the file stem, resolved off
    # the include path the compile step passes.
    module_name = args.material.stem

    wrapper = (args.template.read_text(encoding="utf-8")
               .replace("@MATERIAL_MODULE@", module_name)
               .replace("@MATERIAL_STRUCT@", struct_name))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(wrapper, encoding="utf-8")


if __name__ == "__main__":
    main()
