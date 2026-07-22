#!/usr/bin/env python3
"""KernelEngine Coverage.

Builds + runs the test suite under Clang source-based coverage instrumentation
(native: -fprofile-instr-generate / .profraw / llvm-profdata / llvm-cov;
managed: dotnet test + coverlet), then merges both worlds into a single
ReportGenerator output and prints a structured summary.

Usage:
    python scripts/coverage.py            # full pipeline
    python scripts/coverage.py clean      # wipe build/coverage/
    python scripts/coverage.py report     # re-emit summary from cached data

Everything lives under build/coverage/. The script never writes outside it.

Native coverage scope (post-CMake): the engine build is now root build.zig +
per-plugin build.zig, and almost all engine logic is Zig source, which Zig's
own linker compiles/links directly — it does not go through Clang, so the
old scheme of instrumenting every C/C++ translation unit under src/ no
longer applies (there is no `src/c/kernel/` or `src/cpp/` left to instrument;
both were fully migrated). Verified attempting it anyway on a Zig-linked
shared library fails: Zig's linker rejects Clang's profiling-runtime
relocations ("fatal linker error: unhandled relocation type R_X86_64_PC64
... __llvm_prf_data"). The two GTest suites are the one exception — their
build.zig shells out to the SYSTEM clang++ directly for both compile and
link (an ABI workaround already in place, see tests/c/kernel/build.zig), so
`-Dcoverage=true` there produces real, valid instrumented binaries. That
still surfaces meaningful native signal beyond just the test files
themselves: contract headers with inline definitions get instrumented too,
since they're `#include`d straight into the test translation units.
"""

from __future__ import annotations

import argparse
import datetime
import os
import platform
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# ── Paths ────────────────────────────────────────────────────────────────────

BASE_DIR        = Path(__file__).resolve().parent.parent
COVERAGE_DIR    = BASE_DIR / "build" / "coverage"
ZIG_OUT_DIR     = COVERAGE_DIR / "zig-out"
PROFRAWS_DIR    = COVERAGE_DIR / "profraws"
MANAGED_DIR     = COVERAGE_DIR / "managed"
REPORT_DIR      = COVERAGE_DIR / "report"
MERGED_PROFDATA = COVERAGE_DIR / "merged.profdata"
NATIVE_LCOV     = COVERAGE_DIR / "native.lcov"
SUMMARY_TXT     = COVERAGE_DIR / "summary.txt"

IS_WINDOWS = platform.system().lower() == "windows"
NATIVE_TEST_BINARIES = ["test_ke_kernel", "test_integration_cpp"]

# ── Layer classification ─────────────────────────────────────────────────────
# L3 (auto-generated C# bindings under */Native/Generated/) is excluded from
# analysis up front. "Native" is no longer split into kernel/plugin layers:
# see the module docstring for why only the GTest suites' own translation
# units (plus any contract headers they #include) are instrumented today.

def _norm(p: str) -> str:
    return p.replace("\\", "/")

LAYERS = [
    ("L2", "Native (GTest suites + included headers)",
        lambda p: _norm(p).startswith("tests/") or _norm(p).startswith("src/c/")),
    ("L4", "C# framework",  lambda p: _norm(p).startswith("src/csharp/") and "/Generated/" not in _norm(p)),
]

GAP_THRESHOLD_PCT   = 30.0
GAP_THRESHOLD_LINES = 50

# ── Subprocess helpers ───────────────────────────────────────────────────────

def run(cmd, *, check: bool = True, env: dict | None = None,
        capture: bool = False, cwd: Path | None = None) -> subprocess.CompletedProcess:
    # Long argv (e.g. thousands of profraw paths) is uninteresting noise.
    # Show only the program name and a count of the rest.
    if len(cmd) > 6:
        print(f"  $ {cmd[0]} ... ({len(cmd) - 1} args)")
    else:
        print(f"  $ {' '.join(str(a) for a in cmd)}")
    full_env = os.environ.copy()
    if env: full_env.update(env)
    return subprocess.run(
        [str(a) for a in cmd],
        cwd=str(cwd) if cwd else None,
        env=full_env, check=check, text=True,
        capture_output=capture,
    )

def banner(text: str) -> None:
    print()
    print("-" * 70)
    print(f"  {text}")
    print("-" * 70)

# ── Phase 1: build ────────────────────────────────────────────────────────────

def configure_and_build() -> None:
    banner("[1/4] Build (root build.zig, -Dcoverage=true for the GTest suites)")
    vcpkg_root = os.environ.get("VCPKG_ROOT")
    args = ["zig", "build", "--prefix", str(ZIG_OUT_DIR), "-Dcoverage=true"]
    if vcpkg_root:
        args.append(f"-Dvcpkg-root={vcpkg_root}")
    run(args, cwd=BASE_DIR)

# ── Phase 2: native tests + profile merge ────────────────────────────────────

def run_native_tests() -> list[Path]:
    banner("[2/4] Run native tests (instrumented GTest suites)")
    if PROFRAWS_DIR.exists(): shutil.rmtree(PROFRAWS_DIR)
    PROFRAWS_DIR.mkdir(parents=True)
    bin_dir = ZIG_OUT_DIR / "bin"
    binaries: list[Path] = []
    for name in NATIVE_TEST_BINARIES:
        exe = bin_dir / (f"{name}.exe" if IS_WINDOWS else name)
        if not exe.exists():
            print(f"  (missing {exe} - skipping)")
            continue
        binaries.append(exe)
        # %p (PID) + %m (per-binary id) keeps every run's profraw unique.
        env = {"LLVM_PROFILE_FILE": str(PROFRAWS_DIR / f"{name}-%p-%m.profraw")}
        run([str(exe)], env=env, check=False)
    return binaries

def merge_native_profile(binaries: list[Path]) -> bool:
    profraws = list(PROFRAWS_DIR.glob("*.profraw"))
    if not profraws:
        print("  (no .profraw produced - skipping native LCOV export)")
        return False
    print(f"  Merging {len(profraws)} profraw files -> {MERGED_PROFDATA.name}")
    profraw_list = COVERAGE_DIR / "profraws.list"
    profraw_list.write_text("\n".join(str(p) for p in profraws), encoding="utf-8")
    run(["llvm-profdata", "merge", "-sparse",
         f"-o={MERGED_PROFDATA}", "-f", str(profraw_list)], capture=True)
    if not binaries:
        print("  (no instrumented binaries ran - skipping native LCOV export)")
        return False
    print(f"  Exporting LCOV across {len(binaries)} binaries -> {NATIVE_LCOV.name}")
    first, rest = binaries[0], binaries[1:]
    cmd = ["llvm-cov", "export", "-format=lcov",
           f"-instr-profile={MERGED_PROFDATA}", str(first)]
    cmd += [f"-object={p}" for p in rest]
    with NATIVE_LCOV.open("w", encoding="utf-8") as f:
        subprocess.run(cmd, cwd=BASE_DIR, stdout=f, check=True)
    return True

# ── Phase 3: managed tests ───────────────────────────────────────────────────

def run_managed_tests() -> None:
    banner("[3/4] Run managed (C#) tests")
    if MANAGED_DIR.exists(): shutil.rmtree(MANAGED_DIR)
    MANAGED_DIR.mkdir(parents=True)
    run([
        "dotnet", "test", BASE_DIR / "KernelEngine.slnx",
        "--collect:XPlat Code Coverage",
        "--results-directory", MANAGED_DIR,
        "--nologo", "-v", "m",
        "--",
        "DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura",
    ], check=False)

# ── Phase 4: unified report ──────────────────────────────────────────────────

def build_report() -> None:
    banner("[4/4] Generate unified report")
    if REPORT_DIR.exists(): shutil.rmtree(REPORT_DIR)
    REPORT_DIR.mkdir(parents=True)
    inputs: list[str] = []
    if NATIVE_LCOV.exists() and NATIVE_LCOV.stat().st_size > 0:
        inputs.append(str(NATIVE_LCOV))
    inputs += [str(p) for p in MANAGED_DIR.rglob("*.xml")]
    if not inputs:
        print("  (no coverage data - nothing to report)")
        return
    run([
        "reportgenerator",
        "-reports:" + ";".join(inputs),
        "-targetdir:" + str(REPORT_DIR),
        "-reporttypes:Cobertura;Html",
        "-sourcedirs:" + str(BASE_DIR),
        # *tests* is no longer excluded: the GTest suites' own .cpp files are
        # now the primary native coverage signal (see module docstring).
        "-filefilters:-*Generated*;-*examples*",
        "-classfilters:-*NativeMethods*;-*NativeAnnotation*;-*NativeTypeName*",
    ], check=False)

# ── Structured summary ───────────────────────────────────────────────────────

def _pct(d: dict) -> float:
    return 100.0 * d["covered"] / d["total"] if d["total"] else 0.0

def _module_for(layer: str, path: str) -> str:
    """Group a file path into a coarse module bucket for the summary table."""
    parts = _norm(path).split("/")
    if layer == "L2":
        # tests/c/kernel/... -> tests/c/kernel ; src/c/<domain>/... -> src/c/<domain>
        return "/".join(parts[:3]) if len(parts) >= 3 else "/".join(parts)
    if layer == "L4":
        # src/csharp/<project>/... -> <project>
        return parts[2] if len(parts) >= 3 else "(unknown)"
    return "(unknown)"

def _short(module: str) -> str:
    parts = module.split("/")
    return parts[-1] if parts else module

def print_summary() -> None:
    cobertura = REPORT_DIR / "Cobertura.xml"
    if not cobertura.exists():
        print("\n  (no Cobertura.xml - run the pipeline first)\n")
        return

    root = ET.parse(cobertura).getroot()

    per_layer: dict[str, dict] = {
        lid: {"covered": 0, "total": 0, "modules": {}} for lid, _, _ in LAYERS
    }
    native  = {"covered": 0, "total": 0}
    managed = {"covered": 0, "total": 0}

    base_uri = _norm(str(BASE_DIR)).rstrip("/") + "/"

    for clazz in root.iter("class"):
        file_path = _norm(clazz.get("filename", ""))
        if file_path.startswith(base_uri):
            file_path = file_path[len(base_uri):]
        lines = list(clazz.iter("line"))
        if not lines: continue
        covered = sum(1 for ln in lines if int(ln.get("hits", "0")) > 0)
        total   = len(lines)

        for lid, _, predicate in LAYERS:
            if not predicate(file_path): continue
            L = per_layer[lid]
            L["covered"] += covered
            L["total"]   += total
            module = _module_for(lid, file_path)
            m = L["modules"].setdefault(module, {"covered": 0, "total": 0})
            m["covered"] += covered
            m["total"]   += total
            (native if lid == "L2" else managed)["covered"] += covered
            (native if lid == "L2" else managed)["total"]   += total
            break

    total = {
        "covered": native["covered"] + managed["covered"],
        "total":   native["total"]   + managed["total"],
    }

    out: list[str] = []
    def w(s: str = "") -> None: out.append(s)

    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    w("=" * 70)
    w(f"  KernelEngine Coverage - {now}")
    w("=" * 70)
    w()
    w(f"  TOTAL                                          {_pct(total):5.1f}%   {total['covered']}/{total['total']}")
    w()
    w(f"  Native  (C/C++)                                {_pct(native):5.1f}%   {native['covered']}/{native['total']}")
    w(f"  Managed (C#)                                   {_pct(managed):5.1f}%   {managed['covered']}/{managed['total']}")
    w()
    w("  Per layer:")
    for lid, name, _ in LAYERS:
        L = per_layer[lid]
        w(f"    {lid} - {name:<22} {_pct(L):5.1f}%   {L['covered']}/{L['total']}")
        for module, m in sorted(L["modules"].items()):
            w(f"        {_short(module):<38} {_pct(m):5.1f}%")
    w()
    gaps: list[tuple[str, float, int]] = []
    for lid, _, _ in LAYERS:
        for module, m in per_layer[lid]["modules"].items():
            if m["total"] >= GAP_THRESHOLD_LINES and _pct(m) < GAP_THRESHOLD_PCT:
                gaps.append((module, _pct(m), m["total"]))
    if gaps:
        w(f"  Critical gaps (< {GAP_THRESHOLD_PCT:.0f}% AND > {GAP_THRESHOLD_LINES} lines):")
        for module, p, n in sorted(gaps, key=lambda t: t[1]):
            w(f"    - {_short(module):<38} {p:5.1f}%   ({n} lines)")
        w()
    w(f"  HTML report: {REPORT_DIR / 'index.html'}")
    w("=" * 70)

    text = "\n".join(out)
    SUMMARY_TXT.write_text(text, encoding="utf-8")
    print()
    print(text)

# ── Subcommands ──────────────────────────────────────────────────────────────

def cmd_clean() -> None:
    if COVERAGE_DIR.exists():
        print(f"Removing {COVERAGE_DIR}")
        shutil.rmtree(COVERAGE_DIR)
    else:
        print(f"{COVERAGE_DIR} does not exist.")

def cmd_run() -> None:
    configure_and_build()
    binaries = run_native_tests()
    merge_native_profile(binaries)
    run_managed_tests()
    build_report()
    print_summary()

def cmd_report() -> None:
    print_summary()

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", nargs="?", default="run",
                        choices=["run", "clean", "report"],
                        help="run = full pipeline, clean = wipe build/coverage/, "
                             "report = re-emit summary from cached data")
    args = parser.parse_args()
    {"run": cmd_run, "clean": cmd_clean, "report": cmd_report}[args.action]()

if __name__ == "__main__":
    main()
