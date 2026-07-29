import os
import sys
import glob

def get_rsp_info(rsp_path):
    """Parses an RSP file to find input headers and output directory."""
    inputs = []
    output_dir = "Generated" # Default
    
    with open(rsp_path, 'r') as f:
        lines = f.readlines()
        
    for i in range(len(lines)):
        line = lines[i].strip()
        if line == "--file" and i + 1 < len(lines):
            header = lines[i+1].strip()
            # Resolve relative path based on RSP location
            abs_header = os.path.normpath(os.path.join(os.path.dirname(rsp_path), header))
            inputs.append(abs_header)
        elif line == "--output" and i + 1 < len(lines):
            output_dir = lines[i+1].strip()
            
    abs_output = os.path.normpath(os.path.join(os.path.dirname(rsp_path), output_dir))
    return inputs, abs_output

def check_drift():
    print("Checking for bindings drift (Headers vs Generated C#)...")
    
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    rsp_files = glob.glob(os.path.join(root_dir, "src/csharp/Native/**/*.rsp"), recursive=True)
    
    drift_detected = False
    
    for rsp in rsp_files:
        headers, out_dir = get_rsp_info(rsp)
        
        if not os.path.exists(out_dir):
            print(f"[!] {rsp}: Output directory not found: {out_dir}")
            drift_detected = True
            continue
            
        # Get the newest mtime among headers
        newest_header_time = 0
        newest_header_name = ""
        for h in headers:
            if not os.path.exists(h):
                print(f"[!] {rsp}: Header not found: {h}")
                drift_detected = True
                continue
            mtime = os.path.getmtime(h)
            if mtime > newest_header_time:
                newest_header_time = mtime
                newest_header_name = h
                
        # Get the oldest mtime among generated files (if any exists)
        gen_files = glob.glob(os.path.join(out_dir, "*.cs"))
        if not gen_files:
            print(f"[!] {rsp}: No generated files found in {out_dir}")
            drift_detected = True
            continue
            
        oldest_gen_time = min(os.path.getmtime(f) for f in gen_files)
        
        # If header is newer than generated files, we have drift
        # Adding a 1-second buffer for filesystem precision
        if newest_header_time > oldest_gen_time + 1:
            rel_header = os.path.relpath(newest_header_name, root_dir)
            rel_rsp = os.path.relpath(rsp, root_dir)
            print(f"[DRIFT] {rel_rsp}: Header '{rel_header}' is newer than bindings.")
            drift_detected = True
            
    if drift_detected:
        print("\n[FAIL] Drift detected! Please run 'dotnet run scripts/generate_bindings.cs' and commit the changes.")
        sys.exit(1)
    else:
        print("[OK] All bindings are up to date.")
        sys.exit(0)

if __name__ == "__main__":
    check_drift()
