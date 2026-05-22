import os
import shutil
import subprocess
import sys

def output_dir_for(rsp):
    """Return the absolute --output directory declared inside an .rsp, or None.

    ClangSharp resolves --output relative to the working directory, which we set to the
    .rsp's own folder. multi-file codegen emits one .cs per type there, so wiping this
    directory before regenerating is what drops bindings for types removed from headers.
    """
    rsp_dir = os.path.dirname(rsp)
    with open(rsp, "r", encoding="utf-8") as f:
        lines = [ln.strip() for ln in f.readlines()]
    for i, line in enumerate(lines):
        if line == "--output" and i + 1 < len(lines):
            return os.path.normpath(os.path.join(rsp_dir, lines[i + 1]))
    return None

def run_command(command, cwd=None):
    print(f"Running: {' '.join(command)} in {cwd}")
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"FAILED: {command[-1]}")
        print(f"STDOUT: {result.stdout}")
        print(f"STDERR: {result.stderr}")
    else:
        print(f"SUCCESS: {command[-1]}")
    return result.returncode == 0

def generate():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    csharp_dir = os.path.join(root_dir, "src", "csharp")
    
    print(f"Restoring .NET tools in {csharp_dir}...")
    subprocess.run(["dotnet", "tool", "restore"], cwd=csharp_dir)

    rsp_files = []
    for root, dirs, files in os.walk(csharp_dir):
        # Skip 'bin' and 'obj' folders
        if 'bin' in dirs: dirs.remove('bin')
        if 'obj' in dirs: dirs.remove('obj')
        
        for file in files:
            if file.endswith(".rsp"):
                rsp_files.append(os.path.join(root, file))

    print(f"Found {len(rsp_files)} response files.")
    success_count = 0
    for rsp in rsp_files:
        print(f"\n--- Generating: {os.path.relpath(rsp, root_dir)} ---")
        # Wipe the output dir first so bindings for types removed from the headers don't linger.
        out_dir = output_dir_for(rsp)
        if out_dir and os.path.isdir(out_dir):
            print(f"Cleaning stale bindings in {os.path.relpath(out_dir, root_dir)}")
            shutil.rmtree(out_dir)
        # Run as a local dotnet tool
        if run_command(["dotnet", "tool", "run", "ClangSharpPInvokeGenerator", f"@{rsp}"], cwd=os.path.dirname(rsp)):
            success_count += 1
    
    print(f"\nDone. {success_count}/{len(rsp_files)} bindings regenerated successfully.")

if __name__ == "__main__":
    generate()
