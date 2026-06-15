add_library(ke_spatial INTERFACE)
add_library(ke::spatial ALIAS ke_spatial)
target_include_directories(ke_spatial INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ke_spatial INTERFACE ke_common)
install(TARGETS ke_spatial EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
