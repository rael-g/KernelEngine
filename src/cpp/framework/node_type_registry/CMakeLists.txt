add_library(ke_node_type_registry
    src/node_type_registry.c
)

get_target_property(target_type ke_node_type_registry TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_node_type_registry PUBLIC KE_NODE_TYPE_REGISTRY_STATIC)
else()
    target_compile_definitions(ke_node_type_registry PRIVATE KE_NODE_TYPE_REGISTRY_EXPORT)
endif()

target_include_directories(ke_node_type_registry PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_link_libraries(ke_node_type_registry PUBLIC
    ke_kernel
    ke_framework
)

install(TARGETS ke_node_type_registry
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
