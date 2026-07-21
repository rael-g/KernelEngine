find_package(flecs CONFIG REQUIRED)

add_library(ke_ecs_flecs
    src/ecs_flecs.c
)

target_include_directories(ke_ecs_flecs PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_include_directories(ke_ecs_flecs PRIVATE
    ${CMAKE_SOURCE_DIR}/src/zig/common/src
)

get_target_property(target_type ke_ecs_flecs TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_ecs_flecs PUBLIC KE_ECS_FLECS_STATIC)
else()
    target_compile_definitions(ke_ecs_flecs PRIVATE KE_ECS_FLECS_EXPORT)
endif()

install(DIRECTORY include/ DESTINATION include)

target_link_libraries(ke_ecs_flecs PUBLIC
    ke_ecs
    ke_allocator
    flecs::flecs
)
target_link_libraries(ke_ecs_flecs PRIVATE ke_allocator_malloc)

install(TARGETS ke_ecs_flecs
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
