set(KERNEL_SOURCES
    src/context/allocator.c
    src/common/hash_map.c
    src/common/hash.c
    src/messaging/message_pipe.c
    src/logger/logger.c
    src/logger/console_sink.c
    src/input/input.c
    src/world/world.c
    src/world/scene.c
    src/world/node.c
    src/world/ecs.c
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

add_library(ke::kernel ALIAS ke_kernel)

install(TARGETS ke_kernel
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
