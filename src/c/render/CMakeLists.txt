add_library(ke_render INTERFACE)

target_include_directories(ke_render INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

target_link_libraries(ke_render INTERFACE ke_spatial)

install(TARGETS ke_render EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
