import os
import subprocess
import sys

# Setup paths relative to script location
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.dirname(SCRIPT_DIR)

# Configuration
SHADERC = os.path.join(BASE_DIR, "build", "win", "vcpkg_installed", "x64-windows", "tools", "bgfx", "shaderc.exe")
INCLUDE_DIR = os.path.join(BASE_DIR, "build", "win", "vcpkg_installed", "x64-windows", "include", "bgfx")
SHADERS_SRC_DIR = os.path.join(BASE_DIR, "src", "cpp", "render", "bgfx", "shaders")
SHADERS_OUT_DIR = os.path.join(SHADERS_SRC_DIR, "compiled")
VARYING_DEF = os.path.join(SHADERS_SRC_DIR, "varying.def.sc")

# Profiles for Vulkan (SPIR-V)
PROFILES = {
    "vertex": "spirv",
    "fragment": "spirv",
    "compute": "spirv"
}

def compile_shader(filename):
    if not filename.endswith(".sc") or filename == "varying.def.sc":
        return

    src_path = os.path.join(SHADERS_SRC_DIR, filename)
    out_name = filename.replace(".sc", ".bin")
    out_path = os.path.join(SHADERS_OUT_DIR, out_name)

    shader_type = ""
    if filename.startswith("vs_"):
        shader_type = "vertex"
    elif filename.startswith("fs_"):
        shader_type = "fragment"
    elif filename.startswith("cs_"):
        shader_type = "compute"
    else:
        print(f"Unknown shader type for {filename}, skipping.")
        return

    cmd = [
        SHADERC,
        "-f", src_path,
        "-o", out_path,
        "-i", INCLUDE_DIR,
        "--varyingdef", VARYING_DEF,
        "--type", shader_type,
        "--platform", "windows",
        "-p", PROFILES[shader_type],
        "-O", "3"
    ]

    print(f"Compiling: {filename} -> {out_name}")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"FAILED: {filename}")
            print(result.stderr)
            return False
    except Exception as e:
        print(f"ERROR: {e}")
        return False
    return True

def main():
    if not os.path.exists(SHADERC):
        print(f"Error: shaderc.exe not found at {SHADERC}")
        sys.exit(1)

    if not os.path.exists(SHADERS_OUT_DIR):
        os.makedirs(SHADERS_OUT_DIR)

    files = [f for f in os.listdir(SHADERS_SRC_DIR) if f.endswith(".sc")]
    success_count = 0
    
    for f in files:
        if compile_shader(f):
            success_count += 1

    print(f"\nDone. {success_count}/{len(files) - 1} shaders compiled successfully.")

if __name__ == "__main__":
    main()
