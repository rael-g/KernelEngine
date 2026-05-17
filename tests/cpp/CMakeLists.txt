find_package(GTest CONFIG REQUIRED)
find_package(assimp CONFIG REQUIRED)

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
add_executable(test_renderer_logic
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
    ke_render_core
    GTest::gtest_main
    GTest::gmock
)

add_executable(test_threading
    test_threading.cpp
)

target_include_directories(test_threading PRIVATE 
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/threading/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/core/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/contract/include
)

target_link_libraries(test_threading PRIVATE
    ke_threading
    ke_kernel
    GTest::gtest_main
)

# 3. Asset Logic Tests
add_executable(test_asset_logic
    test_asset_logic.cpp
    ../../src/cpp/asset/assimp/src/AssimpConverter.cpp
    ../../src/cpp/asset/assimp/src/TextureDecoder.cpp
)

target_include_directories(test_asset_logic PRIVATE 
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/asset/assimp/src
)

target_link_libraries(test_asset_logic PRIVATE
    ke_kernel
    assimp::assimp
    GTest::gtest_main
)

enable_coverage(test_cpp_services)
enable_coverage(test_renderer_logic)
enable_coverage(test_threading)
# enable_coverage(test_asset_logic)

gtest_discover_tests(test_cpp_services)
gtest_discover_tests(test_renderer_logic)
gtest_discover_tests(test_threading)
gtest_discover_tests(test_asset_logic)
