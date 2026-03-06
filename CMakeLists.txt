cmake_minimum_required(VERSION 3.15)

project(kernel_engine LANGUAGES C CXX)

include(cmake/Coverage.cmake)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(BUILD_SHARED_LIBS "Build libraries as shared" ON)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

add_subdirectory(src/c/kernel)
add_subdirectory(src/cpp/window/glfw)
add_subdirectory(src/cpp/render/bgfx)
add_subdirectory(src/cpp/render/bgfx_shader_compiler)

add_subdirectory(examples/c/01_minimal_log)
add_subdirectory(examples/c/02_window_graphics)
add_subdirectory(examples/c/03_input_scene)
add_subdirectory(examples/c/04_shader_compile)

enable_testing()
add_subdirectory(tests/c/kernel)
add_subdirectory(tests/cpp)

include(cmake/CodeQuality.cmake)

if(KE_COVERAGE)
    enable_coverage(ke_kernel)
    enable_coverage(ke_render_bgfx)
    enable_coverage(ke_window_glfw)
    enable_coverage(ke_shader_compiler_bgfx)
endif()