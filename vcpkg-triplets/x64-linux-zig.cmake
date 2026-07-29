# Zig-built equivalent of the community x64-linux triplet — same shape
# (dynamic CRT, static library linkage), built with `zig cc`/`zig c++`
# instead of the system gcc/clang, so vcpkg's archives match the ABI of the
# engine's own Zig-built plugins and no standalone C/C++ toolchain needs to
# be installed on the machine.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Linux)
set(VCPKG_ENV_PASSTHROUGH PATH)

set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/zig-linux-toolchain.cmake")
