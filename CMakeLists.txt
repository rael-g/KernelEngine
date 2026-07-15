cmake_minimum_required(VERSION 3.15)

project(kernel_engine LANGUAGES C CXX)

# ── Code coverage (source-based, Clang/LLVM) ─────────────────────────────────
# When KE_COVERAGE=ON, every translation unit under src/ and tests/ is built
# with -fprofile-instr-generate -fcoverage-mapping. New plugins/libraries are
# instrumented automatically — no per-target opt-in. Drives scripts/coverage.py.
option(KE_COVERAGE "Build with Clang source-based coverage instrumentation" OFF)
if(KE_COVERAGE)
    if(NOT CMAKE_C_COMPILER_ID MATCHES "Clang" AND NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        message(FATAL_ERROR "KE_COVERAGE requires Clang (CMake sees ${CMAKE_CXX_COMPILER_ID}).")
    endif()
    message(STATUS "KE_COVERAGE enabled — instrumenting all src/ + tests/ targets.")
    add_compile_options(-fprofile-instr-generate -fcoverage-mapping)
    add_link_options(-fprofile-instr-generate)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(BUILD_SHARED_LIBS "Build libraries as shared" ON)

# Several plugins are shared libraries that link internal static libraries
# (e.g. ke_window_glfw pulls in ke_window_core). ELF targets reject non-PIC
# objects inside a shared object, so position-independent code is required
# everywhere rather than per-target.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# ── Shader compilation (Slang → the active backend's accepted format) ───────
# Set once, here — no render pass decides or names a shader format; each
# resolves its own shader by logical name + stage through
# ke_render_core::load_shader, which asks the device (ke_gpu_device::
# shader_language) and maps that to this same extension. wgsl is the only
# value today because webgpu is the only backend; a second backend changes
# this one line, not any of the passes.
set(KE_SHADER_TARGET "wgsl" CACHE STRING "Shader target format every render pass compiles to (must match the active ke_gpu_device backend)")
find_package(Python3 COMPONENTS Interpreter REQUIRED)
set(KE_COMPILE_SLANG_SCRIPT "${CMAKE_SOURCE_DIR}/scripts/compile_slang.py")
include(cmake/CompileSlangShader.cmake)

# ── Authored materials (the material x pass product) ────────────────────────
# Every .slang across these directories is a lone `struct X : IMaterial` — no
# entry point, no pass import. Each consuming pass compiles all of them
# against its own wrapper template, so adding a material means dropping a file
# in one of these directories: no pass, CMakeLists, or engine source changes.
# The engine's own materials/ ships "standard" (the built-in default) and
# "stripes" (a §6 Mechanism 1 proof); a game APPENDS its own directory here
# rather than overriding, so both keep coexisting.
set(KE_MATERIALS_DIRS "${CMAKE_SOURCE_DIR}/src/shaders/materials" CACHE STRING "Directories of authored IMaterial .slang files (list)")
# Example-owned materials — proves a downstream project can author its own
# shader outside the engine tree, not just swap between engine-shipped ones.
list(APPEND KE_MATERIALS_DIRS "${CMAKE_SOURCE_DIR}/examples/csharp/03_pbr_directional/materials")
set(KE_GENERATE_MATERIAL_WRAPPER_SCRIPT "${CMAKE_SOURCE_DIR}/scripts/generate_material_wrapper.py")
include(cmake/CompileMaterialShaders.cmake)

add_subdirectory(src/c/common)
add_subdirectory(src/c/allocator)
add_subdirectory(src/c/logger)
add_subdirectory(src/c/allocator/malloc)
add_subdirectory(src/zig/logger/simple)
add_subdirectory(src/c/ecs)
add_subdirectory(src/c/spatial)
add_subdirectory(src/c/scheduler)
add_subdirectory(src/c/input)
add_subdirectory(src/c/input/default)
add_subdirectory(src/c/render)
add_subdirectory(src/c/resource_cache)
add_subdirectory(src/cpp/scheduler/enki)
add_subdirectory(src/c/runtime)
add_subdirectory(src/c/framework)
add_subdirectory(src/c/window)
add_subdirectory(src/c/audio)
add_subdirectory(src/c/text)
add_subdirectory(src/c/physics)
add_subdirectory(src/c/asset)
add_subdirectory(src/cpp/window/contract)
add_subdirectory(src/cpp/window/core)
add_subdirectory(src/cpp/window/glfw_device)
add_subdirectory(src/cpp/window/glfw)
add_subdirectory(src/zig/render/tonemap)
add_subdirectory(src/zig/render/skybox)
add_subdirectory(src/zig/render/ui)
add_subdirectory(src/zig/render/gbuffer)
add_subdirectory(src/zig/render/shadow)
add_subdirectory(src/zig/render/cluster)
add_subdirectory(src/zig/render/deferred_lighting)
add_subdirectory(src/zig/render/forward)
add_subdirectory(src/zig/render/core)
add_subdirectory(src/zig/render/webgpu)
add_subdirectory(src/zig/configuration)
add_subdirectory(src/zig/configuration/toml)
add_subdirectory(src/cpp/asset/assimp)
add_subdirectory(src/zig/asset/stb_image)
add_subdirectory(src/zig/audio/miniaudio)
add_subdirectory(src/cpp/physics/box2d)
add_subdirectory(src/zig/text/stb_truetype)

add_subdirectory(examples/c/01_minimal_log)
add_subdirectory(examples/c/05_gpu_device)
add_subdirectory(examples/c/06_triangle)
add_subdirectory(examples/c/07_uniform)
add_subdirectory(examples/c/08_vertex_buffer)
add_subdirectory(examples/c/09_texture)
add_subdirectory(examples/c/10_depth)
add_subdirectory(examples/c/12_render_core)
add_subdirectory(examples/c/13_runtime_clear)
add_subdirectory(examples/c/14_forward_mesh)

enable_testing()
add_subdirectory(tests/c/kernel)
add_subdirectory(tests/cpp)
add_subdirectory(tests/integration/cpp)

include(cmake/CodeQuality.cmake)