add_library(ke_scheduler INTERFACE)
add_library(ke::scheduler ALIAS ke_scheduler)
target_include_directories(ke_scheduler INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ke_scheduler INTERFACE ke_common ke_allocator)
install(TARGETS ke_scheduler EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
