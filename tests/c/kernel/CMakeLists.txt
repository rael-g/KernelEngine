find_package(GTest CONFIG REQUIRED)
add_executable(test_ke_kernel
    test_allocator.cpp
    test_hash_map.cpp
    test_ecs.cpp
    test_input.cpp
    test_logger.cpp
    test_hash.cpp
    test_array.cpp
    test_asset_resolver.cpp  # C-phase 1: re-enabled with new ke_framework plugin
    test_resource_cache.cpp  # C-phase 2: re-enabled as kernel built-in
    # Framework-backed tests still disabled until C-phase reintroduces remaining impls:
    #   test_scene_tree.cpp
    #   test_input_actions.cpp
    #   test_scene_loader.cpp
    #   test_mesh_shape.cpp    -- legacy header API gone; replaced by asset_resolver
    #   test_material_file.cpp -- legacy header API gone; replaced by asset_resolver
    #   test_resource_queue.cpp
)


target_link_libraries(test_ke_kernel PRIVATE
    ke_kernel
    ke_framework
    GTest::gtest_main
)

target_include_directories(test_ke_kernel PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
)

set_target_properties(test_ke_kernel PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

include(GoogleTest)
gtest_discover_tests(test_ke_kernel)
