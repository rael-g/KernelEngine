find_package(GTest CONFIG REQUIRED)

add_executable(test_cpp_services
    test_render_bgfx.cpp
    test_window_glfw.cpp
    test_shader_compiler.cpp
)

target_link_libraries(test_cpp_services PRIVATE
    ke_render_bgfx
    ke_window_glfw
    ke_shader_compiler_bgfx
    GTest::gtest_main
    GTest::gmock
)

target_include_directories(test_cpp_services PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx/include
    ${CMAKE_SOURCE_DIR}/src/cpp/window/glfw/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx_shader_compiler/include
)

set_target_properties(test_cpp_services PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

include(GoogleTest)
gtest_discover_tests(test_cpp_services)

if(KE_COVERAGE)
    enable_coverage(test_cpp_services)
endif()
