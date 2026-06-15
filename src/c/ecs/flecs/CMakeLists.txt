find_package(flecs CONFIG REQUIRED)

add_library(ke_ecs_flecs
    src/ecs_flecs.c
)

target_include_directories(ke_ecs_flecs PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(DIRECTORY include/ DESTINATION include)

target_link_libraries(ke_ecs_flecs PUBLIC
    ke_ecs
    ke_allocator
    flecs::flecs
)

install(TARGETS ke_ecs_flecs
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
