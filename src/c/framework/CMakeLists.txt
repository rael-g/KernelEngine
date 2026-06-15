add_library(ke_framework
    src/world.c
    src/asset_resolver.c
    src/mesh_shape.c
    src/scene_tree.c
    src/input_actions.c
    src/components_apply.c
    src/scene_loader.c
    third_party/tomlc99/toml.c
)

# tomlc99 (vendored) — see third_party/tomlc99/VENDOR.md
target_include_directories(ke_framework PRIVATE
    third_party/tomlc99
)

target_include_directories(ke_framework PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(DIRECTORY include/ DESTINATION include)

target_link_libraries(ke_framework PUBLIC
    ke_common
    ke_allocator
    ke_ecs
    ke_spatial
    ke_input
    ke_render
    ke_asset
    ke_text
    ke_runtime
)

get_target_property(target_type ke_framework TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_framework PUBLIC KE_FRAMEWORK_STATIC)
else()
    target_compile_definitions(ke_framework PRIVATE KE_FRAMEWORK_EXPORT)
endif()

install(TARGETS ke_framework
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
