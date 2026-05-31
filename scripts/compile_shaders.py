"""
compile_shaders.py — compile engine shaders for every bgfx backend.

Usage:
  python compile_shaders.py                  # compile all backends
  python compile_shaders.py --backend spirv  # compile one backend
  python compile_shaders.py --backend spirv,dx11  # compile two backends
  python compile_shaders.py --no-incremental      # force-recompile everything

Output layout:
  src/cpp/render/bgfx/shaders/compiled/{spirv,dx11,dx12,glsl,essl,metal}/{name}.bin

The renderer reads shaders from  <shader_path>/<GetShaderSubdir()>/<name>.bin
where GetShaderSubdir() returns the subdir for the active bgfx backend.
"""

import argparse
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR   = os.path.dirname(SCRIPT_DIR)

SHADERC     = os.path.join(BASE_DIR, "build", "win", "vcpkg_installed", "x64-windows", "tools", "bgfx", "shaderc.exe")
INCLUDE_DIR = os.path.join(BASE_DIR, "build", "win", "vcpkg_installed", "x64-windows", "include", "bgfx")
SHADERS_SRC = os.path.join(BASE_DIR, "src", "cpp", "render", "bgfx", "shaders")
VARYING_DEF = os.path.join(SHADERS_SRC, "varying.def.sc")

# Each entry: subdir name (matches GetShaderSubdir()), shaderc --platform value,
# and per shader-type -p profile strings.
BACKENDS = [
    {
        "subdir":   "spirv",
        "platform": "linux",
        "profiles": {"vertex": "spirv",   "fragment": "spirv",   "compute": "spirv"},
    },
    {
        "subdir":   "dx11",
        "platform": "windows",
        "profiles": {"vertex": "s_5_0",   "fragment": "s_5_0",   "compute": "s_5_0"},
    },
    {
        "subdir":   "dx12",
        "platform": "windows",
        "profiles": {"vertex": "s_6_0",   "fragment": "s_6_0",   "compute": "s_6_0"},
    },
    {
        "subdir":   "glsl",
        "platform": "linux",
        "profiles": {"vertex": "140",     "fragment": "140",     "compute": "430"},
    },
    {
        "subdir":   "essl",
        "platform": "android",
        "profiles": {"vertex": "300_es",  "fragment": "300_es",  "compute": "310_es"},
    },
    {
        "subdir":   "metal",
        "platform": "osx",
        "profiles": {"vertex": "metal",   "fragment": "metal",   "compute": "metal"},
    },
]

def shader_type(filename):
    if filename.startswith("vs_"):  return "vertex"
    if filename.startswith("fs_"):  return "fragment"
    if filename.startswith("cs_"):  return "compute"
    return None

def needs_compile(src, out):
    """True if out is missing or older than src."""
    if not os.path.exists(out):
        return True
    return os.path.getmtime(src) > os.path.getmtime(out)

def compile_shader(src_path, out_path, stype, backend, incremental):
    if incremental and not needs_compile(src_path, out_path):
        return True  # up-to-date

    profile  = backend["profiles"][stype]
    platform = backend["platform"]

    cmd = [
        SHADERC,
        "-f", src_path,
        "-o", out_path,
        "-i", INCLUDE_DIR,
        "--varyingdef", VARYING_DEF,
        "--type", stype,
        "--platform", platform,
        "-p", profile,
        "-O", "3",
    ]

    name = os.path.basename(src_path)
    subdir = backend["subdir"]
    print(f"  [{subdir}] {name}")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"    FAILED: {result.stderr.strip()}")
            return False
    except Exception as e:
        print(f"    ERROR: {e}")
        return False
    return True

def compile_backend(backend, shader_files, incremental):
    subdir     = backend["subdir"]
    out_dir    = os.path.join(SHADERS_SRC, "compiled", subdir)
    os.makedirs(out_dir, exist_ok=True)

    ok = skipped = failed = 0
    for filename in sorted(shader_files):
        stype = shader_type(filename)
        if stype is None:
            continue
        src  = os.path.join(SHADERS_SRC, filename)
        out  = os.path.join(out_dir, filename.replace(".sc", ".bin"))

        if incremental and not needs_compile(src, out):
            skipped += 1
            continue

        if compile_shader(src, out, stype, backend, incremental=False):
            ok += 1
        else:
            failed += 1

    return ok, skipped, failed

def main():
    parser = argparse.ArgumentParser(description="Compile bgfx shaders for one or more backends.")
    parser.add_argument("--backend", default=None,
                        help="Comma-separated backend subdirs to compile (e.g. spirv,dx11). "
                             "Default: all backends.")
    parser.add_argument("--no-incremental", action="store_true",
                        help="Force-recompile all shaders even if output is up-to-date.")
    args = parser.parse_args()

    if not os.path.exists(SHADERC):
        print(f"Error: shaderc.exe not found at {SHADERC}")
        print("Run  cmake --build --preset win  first.")
        sys.exit(1)

    incremental = not args.no_incremental

    selected_subdirs = None
    if args.backend:
        selected_subdirs = {b.strip() for b in args.backend.split(",")}

    backends_to_run = [
        b for b in BACKENDS
        if selected_subdirs is None or b["subdir"] in selected_subdirs
    ]
    if not backends_to_run:
        print(f"No matching backends for: {args.backend}")
        print(f"Available: {', '.join(b['subdir'] for b in BACKENDS)}")
        sys.exit(1)

    shader_files = [f for f in os.listdir(SHADERS_SRC)
                    if f.endswith(".sc") and f != "varying.def.sc"]

    total_ok = total_skipped = total_failed = 0
    for backend in backends_to_run:
        print(f"\n--- {backend['subdir']} ({backend['platform']}) ---")
        ok, skipped, failed = compile_backend(backend, shader_files, incremental)
        total_ok      += ok
        total_skipped += skipped
        total_failed  += failed
        print(f"    compiled={ok}  skipped={skipped}  failed={failed}")

    print(f"\nDone. compiled={total_ok}  skipped={total_skipped}  failed={total_failed}")
    if total_failed:
        sys.exit(1)

if __name__ == "__main__":
    main()
