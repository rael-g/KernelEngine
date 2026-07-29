# Windows equivalent of the community x64-linux triplet (dynamic CRT, static
# library linkage) — same shape, just a different VCPKG_CMAKE_SYSTEM_NAME.
# Built with `zig cc`/`zig c++` via the chainloaded toolchain below instead of
# MSVC, so no Visual Studio / Windows SDK install is required. Static
# archives land with the GNU/ar naming convention (lib*.a), matching Linux.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_ENV_PASSTHROUGH PATH)

set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/zig-mingw-toolchain.cmake")
