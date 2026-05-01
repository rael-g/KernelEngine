find_package(GTest CONFIG REQUIRED)

# 1. Integration Tests (DLL based)
add_executable(test_cpp_services
    test_window_glfw.cpp
    test_shader_compiler.cpp
    test_asset_loader.cpp
)

target_include_directories(test_cpp_services PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/contract/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/core/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/core/src
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx/include
    ${CMAKE_SOURCE_DIR}/src/cpp/window/contract/include
    ${CMAKE_SOURCE_DIR}/src/cpp/window/core/include
    ${CMAKE_SOURCE_DIR}/src/cpp/window/glfw/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx_shader_compiler/include
    ${CMAKE_SOURCE_DIR}/src/cpp/asset/assimp/include
)

target_link_libraries(test_cpp_services PRIVATE
    ke_render_bgfx
    ke_window_glfw
    ke_shader_compiler_bgfx
    ke_asset_assimp
    GTest::gtest_main
    GTest::gmock
)

# 2. Logic Unit Tests (Sources based for 100% coverage reliability)
# Only including systems that are proven to build and run stable
add_executable(test_renderer_logic
    test_native_systems.cpp
    test_geometry_manager.cpp
)

target_include_directories(test_renderer_logic PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/contract/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/core/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/core/src
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx/include
)

target_link_libraries(test_renderer_logic PRIVATE
    ke_render_bgfx
    ke_kernel
    GTest::gtest_main
    GTest::gmock
)

enable_coverage(test_cpp_services)
enable_coverage(test_renderer_logic)

gtest_discover_tests(test_cpp_services)
gtest_discover_tests(test_renderer_logic)
