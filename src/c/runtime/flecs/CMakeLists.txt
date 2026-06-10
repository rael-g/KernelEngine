find_package(flecs CONFIG REQUIRED)

add_library(ke_runtime_flecs
    src/runtime_flecs.c
)

get_target_property(target_type ke_runtime_flecs TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_runtime_flecs PUBLIC KE_RUNTIME_FLECS_STATIC)
else()
    target_compile_definitions(ke_runtime_flecs PRIVATE KE_RUNTIME_FLECS_EXPORT)
endif()

target_include_directories(ke_runtime_flecs PUBLIC
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
)

target_link_libraries(ke_runtime_flecs PUBLIC
    ke_kernel
    flecs::flecs
)

install(TARGETS ke_runtime_flecs
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
