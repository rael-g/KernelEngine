import os
import subprocess
import sys
import re
import platform
import xml.etree.ElementTree as ET
from pathlib import Path

def run_command(cmd, cwd=None, shell=False):
    print(f"Executing: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    result = subprocess.run(cmd, cwd=cwd, shell=shell, text=True)
    if result.returncode != 0:
        print(f"Command failed with exit code {result.returncode}")
        return False
    return True

def get_cmake_preset():
    system = platform.system().lower()
    if system == "windows":
        return "win"
    elif system == "linux":
        return "linux"
    return "base"

def collect_native_coverage():
    print("\n--- Native Coverage Summary (C/C++) ---")
    preset = get_cmake_preset()
    build_dir = Path("build") / preset
    coverage_dir = build_dir / "coverage"
    coverage_dir.mkdir(parents=True, exist_ok=True)
    
    # Pattern to find .gcda files
    gcda_files = list(build_dir.glob("**/*.gcda"))
    results = {}

    for gcda in gcda_files:
        try:
            output = subprocess.check_output(["llvm-cov", "gcov", gcda.name], 
                                           stderr=subprocess.STDOUT, 
                                           text=True,
                                           cwd=gcda.parent)
            
            # Move generated .gcov files to the coverage directory
            for gcov_file in gcda.parent.glob("*.gcov"):
                target_path = coverage_dir / gcov_file.name
                if target_path.exists():
                    os.remove(target_path)
                os.rename(gcov_file, target_path)
        except:
            continue

        lines = output.splitlines()
        current_file = ""
        for line in lines:
            line = line.strip()
            if line.startswith("File '"):
                path_str = line.split("'")[1].replace("\\", "/")
                if "/src/" in path_str:
                    current_file = path_str.split("/src/")[-1]
                else:
                    current_file = ""
            
            elif current_file and line.startswith("Lines executed:"):
                perc_match = re.search(r"Lines executed:(.*)% of", line)
                if perc_match:
                    perc = perc_match.group(1).strip()
                    if not current_file.startswith("..") and "tests/" not in current_file:
                        results[current_file] = perc
                current_file = ""

    for name in sorted(results.keys()):
        print(f"  {name:<40} : {results[name]}%")

def collect_cs_coverage():
    print("\n--- C# Coverage Summary ---")
    root = Path("tests/csharp")
    xml_files = list(root.glob("**/coverage.cobertura.xml"))
    
    combined_results = {}
    for xml_path in xml_files:
        tree = ET.parse(xml_path)
        root_node = tree.getroot()
        for package in root_node.findall(".//package"):
            name = package.get("name")
            line_rate = float(package.get("line-rate")) * 100
            if name not in combined_results or line_rate > combined_results[name]:
                combined_results[name] = line_rate

    for name in sorted(combined_results.keys()):
        print(f"  {name:<40} : {combined_results[name]:.2f}%")

def main():
    preset = get_cmake_preset()
    
    # 1. C Kernel Tests
    print(f"--- Configuring and Building C/C++ with Coverage (Preset: {preset}) ---")
    if not run_command(["cmake", "--preset", preset, "-DKE_COVERAGE=ON"]):
        sys.exit(1)
    
    if not run_command(["cmake", "--build", "--preset", preset]):
        sys.exit(1)
        
    print("\n--- Running Native Tests ---")
    if not run_command(["ctest", "--preset", preset]):
        print("Warning: Some native tests failed.")

    # 2. C# Tests
    print("\n--- Running C# Tests with Coverage ---")
    cs_tests = [
        "tests/csharp/KernelEngine.Kernel.Tests/KernelEngine.Kernel.Tests.csproj",
        "tests/csharp/KernelEngine.Framework.Tests/KernelEngine.Framework.Tests.csproj"
    ]
    
    for test_proj in cs_tests:
        run_command(["dotnet", "test", test_proj, "--collect:XPlat Code Coverage"])

    # 3. Summarize
    collect_native_coverage()
    collect_cs_coverage()
    print("\n--- All Tests and Coverage Complete ---")

if __name__ == "__main__":
    main()
