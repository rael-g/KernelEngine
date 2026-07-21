find_package(GTest CONFIG REQUIRED)
find_package(assimp CONFIG REQUIRED)

# Integration Tests (DLL based)
# These tests link against the full implementations and may interact with hardware/OS.
add_executable(test_integration_cpp
    test_world.cpp
    test_factories.cpp
    test_window_glfw.cpp
    test_asset_loader.cpp
    test_stb_image_loader.cpp
    test_enki_scheduler.cpp
    test_miniaudio_audio.cpp
    test_box2d_physics.cpp
    test_stb_font.cpp
    test_runtime.cpp
    test_ecs_parallel_reads.cpp
)

target_include_directories(test_integration_cpp PRIVATE
    
    ${CMAKE_SOURCE_DIR}/src/cpp/asset/assimp/include
    ${CMAKE_SOURCE_DIR}/src/cpp/asset/stb_image/include
    ${CMAKE_SOURCE_DIR}/src/zig/scheduler/enki/include
    ${CMAKE_SOURCE_DIR}/src/cpp/audio/miniaudio/include
    ${CMAKE_SOURCE_DIR}/src/cpp/physics/box2d/include
    ${CMAKE_SOURCE_DIR}/src/cpp/text/stb_truetype/include
)

target_link_libraries(test_integration_cpp PRIVATE
    ke_window_glfw
    ke_asset_assimp
    ke_asset_stb_image
    ke_scheduler_enki
    ke_audio_miniaudio
    ke_physics_2d_box2d
    ke_text_stb_truetype
    ke_allocator_malloc
    ke_logger_simple
    ke_input_default
    ke_resource_cache_default
    ke_runtime
    ke_ecs_flecs
    ke_framework
    GTest::gtest_main
    GTest::gmock
)

# Run tests from the repo root so paths like "assets/Box.gltf" resolve against
# the on-disk asset tree without requiring per-test copies.
include(GoogleTest)
gtest_discover_tests(test_integration_cpp
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    PROPERTIES LABELS "integration")
