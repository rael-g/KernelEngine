find_package(GTest CONFIG REQUIRED)
add_executable(test_ke_kernel
    test_allocator.cpp
    #   test_hash_map.cpp      -- deleted: hash_map.h removed (domain ejection)
    #   test_ecs.cpp           -- deleted: ke_ecs_registry_create removed (legacy sparse-set ECS replaced by ke_ecs_flecs)
    test_input.cpp
    test_logger.cpp
    #   test_hash.cpp          -- deleted: hash.h removed (domain ejection)
    #   test_array.cpp         -- deleted: array.h removed (domain ejection)
    test_asset_resolver.cpp  # C-phase 1: re-enabled with new ke_framework plugin
    test_resource_cache.cpp  # C-phase 2: re-enabled as kernel built-in
    test_scene_tree.cpp      # C-phase 3: re-enabled with ecs-backed scene_tree
    test_input_actions.cpp   # C-phase 5: re-enabled with pure-C input_actions impl
    test_scene_loader.cpp    # C-phase 6: re-enabled with pure-C scene_loader + apply registry
    #   test_mesh_shape.cpp    -- legacy header API gone; replaced by asset_resolver
    #   test_material_file.cpp -- legacy header API gone; replaced by asset_resolver
    #   test_resource_queue.cpp
)


target_link_libraries(test_ke_kernel PRIVATE
    ke_allocator_malloc
    ke_logger_simple
    ke_input_default
    ke_resource_cache_default
    ke_render_frame_packet
    ke_framework
    ke_runtime
    ke_ecs_flecs
    ke_task_scheduler_enki
    GTest::gtest_main
)

target_include_directories(test_ke_kernel PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/common/include
    ${CMAKE_SOURCE_DIR}/src/c/allocator/include
    ${CMAKE_SOURCE_DIR}/src/c/logger/include
    ${CMAKE_SOURCE_DIR}/src/c/ecs/include
    ${CMAKE_SOURCE_DIR}/src/c/spatial/include
    ${CMAKE_SOURCE_DIR}/src/c/task_scheduler/include
    ${CMAKE_SOURCE_DIR}/src/c/threading/include
    ${CMAKE_SOURCE_DIR}/src/c/runtime/include
    ${CMAKE_SOURCE_DIR}/src/c/framework/include
    ${CMAKE_SOURCE_DIR}/src/c/render/include
    ${CMAKE_SOURCE_DIR}/src/c/input/include
    ${CMAKE_SOURCE_DIR}/src/c/asset/include
    ${CMAKE_SOURCE_DIR}/src/c/resource_cache/include
)

set_target_properties(test_ke_kernel PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

include(GoogleTest)
gtest_discover_tests(test_ke_kernel)
