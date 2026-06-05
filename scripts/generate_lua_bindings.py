#!/usr/bin/env python3
"""Generate Lua FFI cdefs from KernelEngine C headers.

Runs `clang -E` on a curated list of public headers, keeps only declarations
that originate inside our `kernel_engine/...` tree, strips `static inline`
function bodies and MSVC/GCC attributes, and emits a single Lua file that
wraps the cleaned output in `ffi.cdef[[...]]`.

Why this exists: hand-written cdefs drift from the C headers (field-order
mistakes, type mismatches) the moment anyone touches the kernel. Letting the
C compiler resolve `#include`, macros, and conditional compilation removes
that drift; the only thing this script has to do is strip output the FFI
parser cannot eat (function bodies, `__declspec`, `__attribute__`).
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KERNEL_INCLUDE = ROOT / "src" / "c" / "kernel" / "include"

# Plugin public headers we want callable from Lua. Add as new plugins surface.
# The `contract` dirs hold the shared visibility-macro headers that the plugin
# public headers `#include` — they need to be on the include path even though
# we don't directly bind anything from them.
PLUGIN_INCLUDES = [
    ROOT / "src" / "cpp" / "window"  / "contract" / "include",
    ROOT / "src" / "cpp" / "window"  / "glfw"     / "include",
    ROOT / "src" / "cpp" / "render"  / "contract" / "include",
    ROOT / "src" / "cpp" / "render"  / "bgfx"     / "include",
]

# Headers fed to clang. The compiler pulls in everything they transitively
# depend on; the per-source-file filter below keeps only what we want.
HEADERS = [
    "kernel_engine/kernel/context/allocator.h",
    "kernel_engine/kernel/common/handles.h",
    "kernel_engine/kernel/common/math.h",
    "kernel_engine/kernel/common/thread_name.h",
    "kernel_engine/kernel/logger/logger.h",
    "kernel_engine/kernel/input/snapshot.h",
    "kernel_engine/kernel/input/input.h",
    "kernel_engine/kernel/render/light.h",
    "kernel_engine/kernel/render/material.h",
    "kernel_engine/kernel/render/mesh.h",
    "kernel_engine/kernel/render/texture.h",
    "kernel_engine/kernel/render/render.h",
    "kernel_engine/kernel/engine/frame.h",
    "kernel_engine/kernel/engine/frame_packet.h",
    "kernel_engine/kernel/world/ecs.h",
    "kernel_engine/kernel/world/components.h",
    "kernel_engine/kernel/world/system.h",
    "kernel_engine/kernel/world/world.h",
    "kernel_engine/framework/scene_tree.h",
    "kernel_engine/framework/input_actions.h",
    "kernel_engine/framework/mesh_shape.h",
    "kernel_engine/framework/camera_render_system.h",
    "kernel_engine/framework/mesh_render_system.h",
    "kernel_engine/framework/light_render_system.h",
    "kernel_engine/framework/mesh_asset_system.h",
    "kernel_engine/kernel/world/variant.h",
    "kernel_engine/framework/node_type_registry.h",
    "kernel_engine/framework/scene_loader.h",
    "kernel_engine/render/bgfx/bgfx_render.h",
    "kernel_engine/window/glfw/glfw_window.h",
]

OUT = ROOT / "examples" / "lua" / "pong" / "ke_ffi.lua"


def run_clang(headers: list[str]) -> str:
    """Preprocess all headers via a single synthesised translation unit that
    `#include`s each one. Doing it in one invocation lets the header guards
    (`#pragma once` / `#ifndef _H_`) deduplicate transitive includes — feeding
    headers individually to clang produces duplicate typedefs that LuaJIT
    rejects. `-E` keeps `# line` markers so we filter by source file later."""
    umbrella = "\n".join(f'#include <{h}>' for h in headers) + "\n"

    cmd = [
        "clang",
        "-E",
        "-xc",
        "-DKE_KERNEL_STATIC",
        "-DKE_FRAMEWORK_STATIC",
        "-DKE_BGFX_STATIC",
        "-DKE_GLFW_STATIC",
        f"-I{KERNEL_INCLUDE}",
    ]
    for inc in PLUGIN_INCLUDES:
        cmd.append(f"-I{inc}")
    cmd.append("-")  # read source from stdin

    result = subprocess.run(cmd, input=umbrella, capture_output=True,
                            text=True, check=True)
    return result.stdout


# `# 12 "C:\\path\\file.h"` lines from `clang -E`. The path on Windows may have
# either / or \ — we normalise before substring-matching against our include dirs.
LINE_MARKER = re.compile(r'^# \d+ "([^"]+)"(?: \d+)*\s*$')


def filter_kernel_engine(preprocessed: str) -> str:
    """Keep only top-level declarations sourced from our `kernel_engine/...`
    headers. The line markers segment the stream by source file."""
    out: list[str] = []
    keep = False
    for line in preprocessed.splitlines():
        m = LINE_MARKER.match(line)
        if m:
            source = m.group(1).replace("\\", "/")
            keep = "kernel_engine/" in source
            continue
        if keep:
            out.append(line)
    return "\n".join(out)


# Strip MSVC/GCC attribute decorations that LuaJIT FFI's cdef parser rejects.
# `__attribute__((...))` and `__declspec(...)` can carry balanced parens; we
# don't try to nest, since none of our headers chain them at depth > 1.
DECORATIONS = [
    re.compile(r"__attribute__\s*\(\([^)]*\)\)"),
    re.compile(r"__declspec\s*\([^)]*\)"),
    re.compile(r"\b__cdecl\b"),
    re.compile(r"\b__stdcall\b"),
    re.compile(r"\b__forceinline\b"),
    re.compile(r"\b__inline\b"),
]


def strip_decorations(src: str) -> str:
    for r in DECORATIONS:
        src = r.sub("", src)
    return src


def strip_static_inline_bodies(src: str) -> str:
    """Delete every `static inline ... { ... }` definition (with balanced
    braces). LuaJIT's `ffi.cdef` can declare functions but cannot consume their
    bodies — and header-only inlines aren't symbols in the DLL anyway, so they
    are useless to FFI consumers."""
    out: list[str] = []
    i = 0
    n = len(src)
    pat = re.compile(r"\bstatic\s+inline\b")
    while i < n:
        m = pat.search(src, i)
        if not m:
            out.append(src[i:])
            break
        out.append(src[i:m.start()])
        # Walk forward to the function's opening brace, then balance braces.
        brace = src.find("{", m.end())
        if brace < 0:
            out.append(src[m.start():])
            break
        depth = 0
        j = brace
        while j < n:
            c = src[j]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            j += 1
        i = j
    return "".join(out)


def collapse_blank_lines(src: str) -> str:
    return re.sub(r"\n{3,}", "\n\n", src)


def main() -> int:
    missing: list[str] = []
    for h in HEADERS:
        candidates = [KERNEL_INCLUDE / h] + [p / h for p in PLUGIN_INCLUDES]
        if not any(c.is_file() for c in candidates):
            missing.append(h)
    if missing:
        sys.stderr.write("Missing headers:\n  " + "\n  ".join(missing) + "\n")
        return 1

    raw = run_clang(HEADERS)
    cleaned = filter_kernel_engine(raw)
    cleaned = strip_decorations(cleaned)
    cleaned = strip_static_inline_bodies(cleaned)
    cleaned = collapse_blank_lines(cleaned).strip()

    banner = (
        "-- AUTO-GENERATED by scripts/generate_lua_bindings.py. Do not edit by\n"
        "-- hand: regenerate after changing any C header in the source tree.\n"
        "--\n"
        "-- Source headers (preprocessed via `clang -E`, filtered to\n"
        "-- kernel_engine/... declarations, stripped of __declspec/__attribute__\n"
        "-- decorations and `static inline` function bodies):\n"
    )
    for h in HEADERS:
        banner += f"--   {h}\n"

    body = f'local ffi = require("ffi")\n\nffi.cdef[[\n{cleaned}\n]]\n'
    OUT.write_text(banner + "\n" + body, encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)} ({len(body.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
