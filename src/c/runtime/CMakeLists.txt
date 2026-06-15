add_library(ke_runtime
    src/runtime.c
)

get_target_property(target_type ke_runtime TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_runtime PUBLIC KE_RUNTIME_STATIC)
else()
    target_compile_definitions(ke_runtime PRIVATE KE_RUNTIME_EXPORT)
endif()

target_include_directories(ke_runtime PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

target_link_libraries(ke_runtime PUBLIC
    ke_common
    ke_allocator
    ke_ecs
    ke_task_scheduler
    ke_kernel
)

install(TARGETS ke_runtime
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
