find_package(GTest CONFIG REQUIRED)
add_executable(test_ke_kernel
    test_allocator.cpp
    test_hash_map.cpp
    test_ecs.cpp
    test_input.cpp
    test_logger.cpp
    test_hash.cpp
    test_array.cpp
    # Framework-backed tests disabled until C-phase rewrite reintroduces ke_world:
    #   test_resource_cache.cpp
    #   test_scene_tree.cpp
    #   test_input_actions.cpp
    #   test_scene_loader.cpp
    #   test_mesh_shape.cpp
    #   test_material_file.cpp
    #   test_asset_resolver.cpp
    #   test_resource_queue.cpp
)


target_link_libraries(test_ke_kernel PRIVATE
    ke_kernel
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
