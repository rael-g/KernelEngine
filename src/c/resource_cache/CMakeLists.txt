add_library(ke_resource_cache INTERFACE)
add_library(ke::resource_cache ALIAS ke_resource_cache)

target_include_directories(ke_resource_cache INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ke_resource_cache INTERFACE ke_common)

add_subdirectory(${CMAKE_SOURCE_DIR}/src/zig/resource_cache/default ${CMAKE_BINARY_DIR}/src/zig/resource_cache/default)

install(TARGETS ke_resource_cache EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
