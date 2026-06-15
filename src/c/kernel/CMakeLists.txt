set(KERNEL_SOURCES
    src/context/allocator.c
    src/input/input.c
    src/logger/logger.c
    src/resource_cache/resource_cache.c
    src/engine/frame_packet.c
    src/threading/thread_name.c
)

add_library(ke_kernel ${KERNEL_SOURCES})

get_target_property(target_type ke_kernel TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_kernel PUBLIC KE_KERNEL_STATIC)
else()
    target_compile_definitions(ke_kernel PRIVATE KE_KERNEL_EXPORT)
endif()

target_include_directories(ke_kernel PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_include_directories(ke_kernel PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/threading/include
)

target_link_libraries(ke_kernel PUBLIC
    ke_common
    ke_allocator
    ke_logger
    ke_ecs
    ke_spatial
    ke_task_scheduler
    ke_input
    ke_render
)

add_library(ke::kernel ALIAS ke_kernel)

install(TARGETS ke_kernel
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
