add_library(ke_window_contract INTERFACE)

target_include_directories(ke_window_contract INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(TARGETS ke_window_contract EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
