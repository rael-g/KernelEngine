find_package(GTest CONFIG REQUIRED)
find_package(assimp CONFIG REQUIRED)

# 1. Logic Unit Tests (Sources based for 100% coverage reliability)
# These tests focus on core engine logic using Mocks for hardware/plugins.
add_executable(test_renderer_logic
    test_render_contract.cpp
    test_geometry_manager.cpp
    test_lighting_manager.cpp
    test_texture_manager.cpp
    test_render_graph_impl.cpp
    test_shadow_pipeline.cpp
    test_post_process_pipeline.cpp
    test_clustered_forward.cpp
    test_core_renderer.cpp
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

# 2. Asset Logic Tests
add_executable(test_asset_logic
    test_asset_logic.cpp
    ../../src/cpp/asset/assimp/src/assimp_converter.cpp
    ../../src/cpp/asset/assimp/src/texture_decoder.cpp
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

gtest_discover_tests(test_renderer_logic)
gtest_discover_tests(test_threading)
gtest_discover_tests(test_asset_logic)
