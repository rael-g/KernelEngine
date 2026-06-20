add_library(ke_allocator INTERFACE)
add_library(ke::allocator ALIAS ke_allocator)
target_include_directories(ke_allocator INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
install(TARGETS ke_allocator EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
