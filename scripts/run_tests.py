import os
import subprocess
import sys
import re
import platform
import xml.etree.ElementTree as ET
from pathlib import Path
import shutil

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

def clean_gcda():
    preset = get_cmake_preset()
    build_dir = Path("build") / preset
    if build_dir.exists():
        print(f"Cleaning .gcda files in {build_dir}...")
        for gcda in build_dir.glob("**/*.gcda"):
            try:
                gcda.unlink()
            except:
                pass

def collect_native_coverage():
    print("\n--- Native Coverage Summary (C/C++) ---")
    preset = get_cmake_preset()
    build_dir = Path("build") / preset
    coverage_dir = build_dir / "coverage"
    coverage_dir.mkdir(parents=True, exist_ok=True)
    
    # Identify all source files that SHOULD be covered
    all_src_files = []
    for ext in ['*.c', '*.cpp', '*.cc', '*.h', '*.hh']:
        for f in Path("src/c").glob(f"**/{ext}"):
            all_src_files.append(f.as_posix())
        for f in Path("src/cpp").glob(f"**/{ext}"):
            all_src_files.append(f.as_posix())
    
    # Pattern to find .gcda files
    gcda_files = list(build_dir.glob("**/*.gcda"))
    results = {}

    for gcda in gcda_files:
        try:
            output = subprocess.check_output(["llvm-cov", "gcov", "-p", gcda.name], 
                                           stderr=subprocess.STDOUT, 
                                           text=True,
                                           cwd=gcda.parent)
            
            # Move generated .gcov files to the coverage directory
            for gcov_file in gcda.parent.glob("*.gcov"):
                target_path = coverage_dir / gcov_file.name
                if target_path.exists():
                    os.remove(target_path)
                os.rename(gcov_file, target_path)
        except Exception as e:
            # print(f"Error processing {gcda}: {e}")
            continue

        lines = output.splitlines()
        current_file = ""
        for line in lines:
            line = line.strip()
            if line.startswith("File '"):
                path_str = line.split("'")[1].replace("\\", "/")
                # Try to match with our src files
                matched_path = ""
                if "/src/" in path_str:
                    suffix = path_str.split("/src/")[-1]
                    # Search in all_src_files for something ending with suffix
                    for src in all_src_files:
                        if src.endswith(suffix):
                            matched_path = src
                            break
                
                if matched_path:
                    current_file = matched_path
                else:
                    current_file = ""
            
            elif current_file and line.startswith("Lines executed:"):
                perc_match = re.search(r"Lines executed:(.*)% of", line)
                if perc_match:
                    perc = perc_match.group(1).strip()
                    results[current_file] = float(perc)
                current_file = ""

    # Add 0% for files that were not found in gcda but are in src
    for src in all_src_files:
        if src not in results:
            results[src] = 0.0

    for name in sorted(results.keys()):
        print(f"  {name:<60} : {results[name]:>6.2f}%")

def collect_cs_coverage():
    print("\n--- C# Coverage Summary ---")
    
    # Identify all projects that SHOULD be covered
    all_projects = []
    for csproj in Path("src/csharp").glob("**/*.csproj"):
        if ".Native" not in csproj.name:
            all_projects.append(csproj.stem)
            
    root = Path("tests/csharp")
    xml_files = list(root.glob("**/bin/TestResults/**/coverage.cobertura.xml"))
    
    combined_results = {proj: 0.0 for proj in all_projects}
    
    for xml_path in xml_files:
        try:
            tree = ET.parse(xml_path)
            root_node = tree.getroot()
            for package in root_node.findall(".//package"):
                name = package.get("name")
                if ".Native" in name:
                    continue
                line_rate = float(package.get("line-rate")) * 100
                if name in combined_results:
                    if line_rate > combined_results[name]:
                        combined_results[name] = line_rate
                else:
                    # Some packages might have different names, try matching by prefix
                    for proj in all_projects:
                        if name.startswith(proj):
                            if line_rate > combined_results[proj]:
                                combined_results[proj] = line_rate
        except:
            continue

    for name in sorted(combined_results.keys()):
        print(f"  {name:<40} : {combined_results[name]:>6.2f}%")

def clean_cs_results():
    root = Path("tests/csharp")
    if root.exists():
        print(f"Cleaning C# test results in {root}...")
        for tr in root.glob("**/bin/TestResults"):
            if tr.is_dir():
                shutil.rmtree(tr)

def main():
    preset = get_cmake_preset()
    
    # 0. Clean old coverage data
    clean_gcda()
    clean_cs_results()

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
    # Find all test projects
    cs_test_projects = list(Path("tests/csharp").glob("**/*.Tests.csproj"))
    
    for test_proj in cs_test_projects:
        run_command([
            "dotnet", "test", str(test_proj), 
            "--collect:XPlat Code Coverage", 
            "--results-directory", str(test_proj.parent / "bin" / "TestResults"),
            "--", 
            "DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura",
            "DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Include=[KernelEngine.*]*",
            "DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Exclude=[*Native*]*"
        ])

    # 3. Summarize
    collect_native_coverage()
    collect_cs_coverage()
    print("\n--- All Tests and Coverage Complete ---")

if __name__ == "__main__":
    main()
