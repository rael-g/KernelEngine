add_library(ke_resource_cache
    src/resource_cache.c
)

get_target_property(target_type ke_resource_cache TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_resource_cache PUBLIC KE_RESOURCE_CACHE_STATIC)
else()
    target_compile_definitions(ke_resource_cache PRIVATE KE_RESOURCE_CACHE_EXPORT)
endif()

target_include_directories(ke_resource_cache PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_link_libraries(ke_resource_cache PUBLIC
    ke_kernel
    ke_framework
)

install(TARGETS ke_resource_cache
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
