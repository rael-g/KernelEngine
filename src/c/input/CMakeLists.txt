add_library(ke_input INTERFACE)

target_include_directories(ke_input INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(TARGETS ke_input EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
