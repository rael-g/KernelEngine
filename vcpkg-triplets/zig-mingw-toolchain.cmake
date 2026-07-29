# Chainloaded by x64-windows-zig.cmake. Points vcpkg's CMake-based ports at
# `zig cc`/`zig c++` (targeting x86_64-windows-gnu) instead of a real MSVC or
# mingw-w64 install — Zig bundles its own mingw-w64 headers/CRT/import libs,
# so nothing else needs to be installed on the machine. Validated against
# glfw3 and assimp (the project's heaviest C++ port) — see ZigMigrationPlan.md
# §3 risk 1 for why this route (Clang + GNU/mingw ABI) was preferred over MSVC.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

set(CMAKE_C_COMPILER "${CMAKE_CURRENT_LIST_DIR}/zig-cc.cmd")
set(CMAKE_CXX_COMPILER "${CMAKE_CURRENT_LIST_DIR}/zig-cxx.cmd")
set(CMAKE_AR "${CMAKE_CURRENT_LIST_DIR}/zig-ar.cmd" CACHE FILEPATH "" FORCE)
set(CMAKE_RANLIB "${CMAKE_CURRENT_LIST_DIR}/zig-ranlib.cmd" CACHE FILEPATH "" FORCE)

set(CMAKE_C_COMPILER_WORKS TRUE)
set(CMAKE_CXX_COMPILER_WORKS TRUE)
