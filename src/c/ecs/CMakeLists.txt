add_library(ke_ecs INTERFACE)
add_library(ke::ecs ALIAS ke_ecs)
target_include_directories(ke_ecs INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ke_ecs INTERFACE ke_allocator ke_common)
install(TARGETS ke_ecs EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)

add_subdirectory(flecs)
