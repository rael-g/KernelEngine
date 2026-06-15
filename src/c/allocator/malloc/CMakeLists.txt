add_library(ke_allocator_malloc STATIC
    src/allocator_malloc.c
)
add_library(ke::allocator_malloc ALIAS ke_allocator_malloc)

get_target_property(target_type ke_allocator_malloc TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_allocator_malloc PUBLIC KE_KERNEL_STATIC)
else()
    target_compile_definitions(ke_allocator_malloc PRIVATE KE_KERNEL_EXPORT)
endif()

target_link_libraries(ke_allocator_malloc PUBLIC ke_allocator ke_logger)

install(TARGETS ke_allocator_malloc
    EXPORT KernelEngineTargets
    ARCHIVE DESTINATION lib
)
