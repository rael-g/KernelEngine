# Chainloaded by x64-linux-zig.cmake. Points vcpkg's CMake-based ports at
# `zig cc`/`zig c++` instead of the system gcc/clang + binutils.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_C_COMPILER "${CMAKE_CURRENT_LIST_DIR}/zig-cc.sh")
set(CMAKE_CXX_COMPILER "${CMAKE_CURRENT_LIST_DIR}/zig-cxx.sh")
set(CMAKE_AR "${CMAKE_CURRENT_LIST_DIR}/zig-ar.sh" CACHE FILEPATH "" FORCE)
set(CMAKE_RANLIB "${CMAKE_CURRENT_LIST_DIR}/zig-ranlib.sh" CACHE FILEPATH "" FORCE)

set(CMAKE_C_COMPILER_WORKS TRUE)
set(CMAKE_CXX_COMPILER_WORKS TRUE)

# Needed by Find modules using multiarch paths (FindX11, FindGL, ...) to see
# /usr/lib/x86_64-linux-gnu.
set(CMAKE_LIBRARY_ARCHITECTURE "x86_64-linux-gnu")
