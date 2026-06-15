add_library(ke_window INTERFACE)

target_include_directories(ke_window INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(TARGETS ke_window EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
