add_library(ke_framework
    src/node_type_registry.c
    src/resource_cache.c
    src/scene_tree.c
)

get_target_property(target_type ke_framework TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_framework PUBLIC KE_FRAMEWORK_STATIC)
else()
    target_compile_definitions(ke_framework PRIVATE KE_FRAMEWORK_EXPORT)
endif()

target_link_libraries(ke_framework PUBLIC
    ke_kernel
)

install(TARGETS ke_framework
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
