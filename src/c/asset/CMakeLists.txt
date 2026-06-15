add_library(ke_asset INTERFACE)

target_include_directories(ke_asset INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# asset headers depend on kernel common types and font contract
target_link_libraries(ke_asset INTERFACE ke_kernel ke_text)

install(TARGETS ke_asset EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
