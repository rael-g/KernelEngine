add_library(ke_threading_default STATIC
    src/thread_name.c
)
add_library(ke::threading_default ALIAS ke_threading_default)

get_target_property(target_type ke_threading_default TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_threading_default PUBLIC KE_KERNEL_STATIC)
else()
    target_compile_definitions(ke_threading_default PRIVATE KE_KERNEL_EXPORT)
endif()

# Use include dir directly — ke_threading (C++ lib) is not yet in graph here.
target_include_directories(ke_threading_default PUBLIC
    ${CMAKE_SOURCE_DIR}/src/c/threading/include
)
target_link_libraries(ke_threading_default PUBLIC ke_common)

install(TARGETS ke_threading_default
    EXPORT KernelEngineTargets
    ARCHIVE DESTINATION lib
)
