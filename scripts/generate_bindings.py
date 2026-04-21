import os
import subprocess
import sys

def run_command(command, cwd=None):
    print(f"Running: {' '.join(command)}")
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
    print("Restoring .NET tools...")
    subprocess.run(["dotnet", "tool", "restore"], cwd=root_dir)

    native_dir = os.path.join(root_dir, "src", "csharp", "Native")
    rsp_files = []
    for root, dirs, files in os.walk(native_dir):
        for file in files:
            if file.endswith(".rsp"):
                rsp_files.append(os.path.join(root, file))

    print(f"Found {len(rsp_files)} response files.")
    success_count = 0
    for rsp in rsp_files:
        print(f"\n--- Generating: {os.path.relpath(rsp, root_dir)} ---")
        if run_command(["dotnet", "clangsharp", f"@{rsp}"], cwd=os.path.dirname(rsp)):
            success_count += 1
    
    print(f"\nDone. {success_count}/{len(rsp_files)} bindings regenerated successfully.")

if __name__ == "__main__":
    generate()
