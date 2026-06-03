add_library(ke_scene_tree
    src/scene_tree.c
)

get_target_property(target_type ke_scene_tree TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_scene_tree PUBLIC KE_SCENE_TREE_STATIC)
else()
    target_compile_definitions(ke_scene_tree PRIVATE KE_SCENE_TREE_EXPORT)
endif()

target_include_directories(ke_scene_tree PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_link_libraries(ke_scene_tree PUBLIC
    ke_kernel
    ke_framework
)

install(TARGETS ke_scene_tree
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
