add_library(ke_physics INTERFACE)

target_include_directories(ke_physics INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(TARGETS ke_physics EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
