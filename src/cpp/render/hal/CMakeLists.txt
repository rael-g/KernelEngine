add_library(ke_render_hal INTERFACE)

target_include_directories(ke_render_hal INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(TARGETS ke_render_hal EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
