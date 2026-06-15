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

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

add_subdirectory(src/c/common)
add_subdirectory(src/c/allocator)
add_subdirectory(src/c/logger)
add_subdirectory(src/c/ecs)
add_subdirectory(src/c/spatial)
add_subdirectory(src/c/task_scheduler)
add_subdirectory(src/c/kernel)
add_subdirectory(src/cpp/task_scheduler/enki)
add_subdirectory(src/c/runtime)
add_subdirectory(src/c/framework)
add_subdirectory(src/c/window)
add_subdirectory(src/c/audio)
add_subdirectory(src/c/text)
add_subdirectory(src/c/physics)
add_subdirectory(src/c/input)
add_subdirectory(src/c/asset)
add_subdirectory(src/c/render)
add_subdirectory(src/cpp/threading)
add_subdirectory(src/cpp/window/contract)
add_subdirectory(src/cpp/window/core)
add_subdirectory(src/cpp/window/glfw_device)
add_subdirectory(src/cpp/window/glfw)
add_subdirectory(src/cpp/render/contract)
add_subdirectory(src/cpp/render/core)
add_subdirectory(src/cpp/render/bgfx_device)
add_subdirectory(src/cpp/render/bgfx)
add_subdirectory(src/cpp/render/bgfx_shader_compiler)
add_subdirectory(src/cpp/asset/assimp)
add_subdirectory(src/cpp/asset/stb_image)
add_subdirectory(src/cpp/audio/miniaudio)
add_subdirectory(src/cpp/physics/box2d)
add_subdirectory(src/cpp/text/stb_truetype)

add_subdirectory(examples/c/01_minimal_log)
# 02_window_graphics + 03_input_scene depend on legacy ke_world, removed in B0.
# Re-enable after C-phase rewrite reintroduces ke_world in framework plugin.
# add_subdirectory(examples/c/02_window_graphics)
# add_subdirectory(examples/c/03_input_scene)
add_subdirectory(examples/c/04_shader_compile)

enable_testing()
add_subdirectory(tests/c/kernel)
add_subdirectory(tests/cpp)
add_subdirectory(tests/integration/cpp)

include(cmake/CodeQuality.cmake)