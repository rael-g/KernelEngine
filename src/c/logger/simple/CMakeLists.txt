add_library(ke_logger_simple STATIC
    src/logger_simple.c
)
add_library(ke::logger_simple ALIAS ke_logger_simple)

get_target_property(target_type ke_logger_simple TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_logger_simple PUBLIC KE_KERNEL_STATIC)
else()
    target_compile_definitions(ke_logger_simple PRIVATE KE_KERNEL_EXPORT)
endif()

target_link_libraries(ke_logger_simple PUBLIC ke_logger ke_allocator ke_allocator_malloc)

install(TARGETS ke_logger_simple
    EXPORT KernelEngineTargets
    ARCHIVE DESTINATION lib
)
