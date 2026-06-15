add_library(ke_audio INTERFACE)

target_include_directories(ke_audio INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(TARGETS ke_audio EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
