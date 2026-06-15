add_library(ke_common INTERFACE)
add_library(ke::common ALIAS ke_common)
target_include_directories(ke_common INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
install(TARGETS ke_common EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
