find_package(GTest CONFIG REQUIRED)

add_executable(test_cpp_services
    test_render_bgfx.cpp
    test_window_glfw.cpp
    test_shader_compiler.cpp
    test_asset_loader.cpp
)

# Explicitly add directories so we can use #include <bgfx_renderer.hpp> etc.
target_include_directories(test_cpp_services PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx/src
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx/include
    ${CMAKE_SOURCE_DIR}/src/cpp/window/glfw/src
    ${CMAKE_SOURCE_DIR}/src/cpp/window/glfw/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx_shader_compiler/include
)

target_link_libraries(test_cpp_services PRIVATE
    ke_render_bgfx
    ke_window_glfw
    ke_shader_compiler_bgfx
    ke_asset_assimp
    GTest::gtest_main
    GTest::gmock
)

gtest_discover_tests(test_cpp_services)
