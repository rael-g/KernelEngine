import os
import subprocess
import sys
import platform
import shutil
import tempfile
from pathlib import Path

# --- Configuration ---
PROJECT_NAME = "KernelEngine"
BASE_DIR = Path(__file__).resolve().parent.parent
TEMP_DIR = Path(tempfile.gettempdir()) / f"{PROJECT_NAME}_Coverage"

# Add Python scripts to PATH for gcovr
GCOVR_PATH = os.path.expandvars(r"%APPDATA%\Python\Python311\Scripts")
if GCOVR_PATH not in os.environ["PATH"]:
    os.environ["PATH"] += os.pathsep + GCOVR_PATH

def run_command(cmd, cwd=None, shell=False, env=None, capture=False):
    if isinstance(cmd, list): cmd = [str(arg) for arg in cmd] 
    cmd_str = " ".join(cmd) if isinstance(cmd, list) else str(cmd)
    print(f"\n>> Executing: {cmd_str}")
    full_env = os.environ.copy()
    if env: full_env.update(env)

    if capture:
        result = subprocess.run(cmd, cwd=cwd, shell=shell, text=True, env=full_env, capture_output=True)
    else:
        result = subprocess.run(cmd, cwd=cwd, shell=shell, text=True, env=full_env)

    return result

def to_gcovr_path(p):
    return str(p).replace("\\", "/")

def main():
    preset = "win" if platform.system().lower() == "windows" else "linux"
    print("=" * 70)
    print(f" {PROJECT_NAME} - Professional Structured Coverage v30")
    print("=" * 70)

    if TEMP_DIR.exists(): shutil.rmtree(TEMP_DIR)
    TEMP_DIR.mkdir(parents=True)
    results_dir = TEMP_DIR / "results"
    report_dir = TEMP_DIR / "report"
    results_dir.mkdir(); report_dir.mkdir()

    # 1. Native C/C++
    print("\n[1/3] Processing Native Modules...")
    run_command(["cmake", "--preset", preset, "-DKE_COVERAGE=ON"], cwd=BASE_DIR)
    run_command(["cmake", "--build", "--preset", preset], cwd=BASE_DIR)

    build_dir = BASE_DIR / "build" / preset
    for gcda in build_dir.glob("**/*.gcda"): gcda.unlink()    
    run_command(["ctest", "--preset", preset, "--output-on-failure"], cwd=BASE_DIR)

    native_modules = {
        "Native.Kernel":        "src/c/kernel",
        "Native.Render":        "src/cpp/render",
        "Native.Window":        "src/cpp/window",
        "Native.Threads":       "src/cpp/threading",
        "Native.Assets":        "src/cpp/asset",
        "Native.Audio":         "src/cpp/audio",
        "Native.DevPlatform":   "src/cpp/dev_platform",
        "Native.Physics":       "src/cpp/physics",
        "Native.TaskScheduler": "src/cpp/task_scheduler",
        "Native.Text":          "src/cpp/text",
    }

    # Use gcovr to create organized XMLs
    for module_name, module_path in native_modules.items():   
        xml_output = results_dir / f"{module_name}.xml"       
        print(f"  > Capturing {module_name}...")

        gcovr_cmd = [
            "python", "-m", "gcovr",
            "-r", ".",
            to_gcovr_path(build_dir),
            "--gcov-executable", "llvm-cov gcov",
            "--cobertura", to_gcovr_path(xml_output),
            "--filter", module_path,
            "--exclude", ".*tests.*"
        ]

        res = run_command(gcovr_cmd, cwd=BASE_DIR, capture=True)
        if res.returncode != 0:
            print(f"    ! gcovr error for {module_name}: {res.stderr[:200]}")
        
        # Clean any gcov files that popped up in BASE_DIR immediately
        for f in BASE_DIR.glob("*.gcov"): f.unlink()

    # 2. Managed C#
    print("\n[2/3] Processing Managed Modules...")
    run_command([
        "dotnet", "test", BASE_DIR / "KernelEngine.slnx",     
        "--collect:XPlat Code Coverage",
        "--results-directory", results_dir,
        "--nologo", "-v", "m", 
        "--",
        "DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura"
    ], cwd=BASE_DIR)

    # 3. Unified Report        
    print("\n[3/3] Generating Structured Summary...")

    report_cmd = [
        "reportgenerator",     
        f"-reports:{results_dir}/**/*.xml",
        f"-targetdir:{report_dir}",
        "-reporttypes:TextSummary;HtmlSummary",
        "-assemblyfilters:+*", 
        f"-sourcedirs:{BASE_DIR}",
        "-filefilters:-*tests*;+*src/c*;+*src/cpp*;+*src/csharp*",
        "-classfilters:-*NativeMethods*;-*NativeAnnotation*;-*NativeTypeName*"
    ]

    if run_command(report_cmd, cwd=BASE_DIR).returncode == 0:
        summary_txt = report_dir / "Summary.txt"
        if summary_txt.exists():
            print("\n" + "-" * 70)
            print(summary_txt.read_text(encoding="utf-8"))
            print("-" * 70)
            print(f"\nFull Report: {report_dir / 'index.html'}")

    # 4. Cleanup & Environment Restore
    print("\n[Cleanup] Restoring environment...")
    run_command(["cmake", "--preset", preset, "-DKE_COVERAGE=OFF"], cwd=BASE_DIR)
    for gcda in build_dir.glob("**/*.gcda"): gcda.unlink()
    for gcno in build_dir.glob("**/*.gcno"): gcno.unlink()
    for f in BASE_DIR.glob("*.gcov"): f.unlink()

if __name__ == "__main__":     
    main()
