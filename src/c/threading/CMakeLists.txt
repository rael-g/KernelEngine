add_library(ke_threading INTERFACE)
add_library(ke::threading ALIAS ke_threading)
target_include_directories(ke_threading INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ke_threading INTERFACE ke_allocator ke_common)
install(TARGETS ke_threading EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
