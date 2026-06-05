find_package(GTest CONFIG REQUIRED)
find_package(assimp CONFIG REQUIRED)

# 1. Integration Tests (DLL based)
add_executable(test_cpp_services
    test_window_glfw.cpp
    test_shader_compiler.cpp
    test_asset_loader.cpp
    test_stb_image_loader.cpp
    test_enki_task_scheduler.cpp
    test_miniaudio_audio.cpp
    test_box2d_physics.cpp
    test_stb_font.cpp
    test_glfw_window_device.cpp
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
    ${CMAKE_SOURCE_DIR}/src/cpp/window/glfw_device/src
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx_shader_compiler/include
    ${CMAKE_SOURCE_DIR}/src/cpp/asset/assimp/include
    ${CMAKE_SOURCE_DIR}/src/cpp/asset/stb_image/include
    ${CMAKE_SOURCE_DIR}/src/cpp/task_scheduler/enki/include
    ${CMAKE_SOURCE_DIR}/src/cpp/audio/miniaudio/include
    ${CMAKE_SOURCE_DIR}/src/cpp/physics/box2d/include
    ${CMAKE_SOURCE_DIR}/src/cpp/text/stb_truetype/include
)

target_link_libraries(test_cpp_services PRIVATE
    ke_render_bgfx
    ke_window_glfw
    ke_window_glfw_device
    ke_shader_compiler_bgfx
    ke_asset_assimp
    ke_asset_stb_image
    ke_task_scheduler_enki
    ke_audio_miniaudio
    ke_physics_2d_box2d
    ke_text_stb_truetype
    GTest::gtest_main
    GTest::gmock
)

# 2. Logic Unit Tests (Sources based for 100% coverage reliability)
add_executable(test_renderer_logic
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

# 3. Asset Logic Tests
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

gtest_discover_tests(test_cpp_services)
gtest_discover_tests(test_renderer_logic)
gtest_discover_tests(test_threading)
gtest_discover_tests(test_asset_logic)
