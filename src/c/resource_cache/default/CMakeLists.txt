add_library(ke_resource_cache_default STATIC
    src/resource_cache.c
)
add_library(ke::resource_cache_default ALIAS ke_resource_cache_default)

get_target_property(target_type ke_resource_cache_default TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_resource_cache_default PUBLIC KE_KERNEL_STATIC)
else()
    target_compile_definitions(ke_resource_cache_default PRIVATE KE_KERNEL_EXPORT)
endif()

target_link_libraries(ke_resource_cache_default PUBLIC ke_resource_cache ke_allocator ke_allocator_malloc)

install(TARGETS ke_resource_cache_default
    EXPORT KernelEngineTargets
    ARCHIVE DESTINATION lib
)
