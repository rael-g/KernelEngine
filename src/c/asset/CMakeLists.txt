add_library(ke_asset INTERFACE)

target_include_directories(ke_asset INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

target_link_libraries(ke_asset INTERFACE ke_common ke_render ke_text ke_scheduler)

install(TARGETS ke_asset EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
