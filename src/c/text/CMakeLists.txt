add_library(ke_text INTERFACE)

target_include_directories(ke_text INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(TARGETS ke_text EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
