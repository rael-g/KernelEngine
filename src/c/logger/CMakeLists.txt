add_library(ke_logger INTERFACE)
add_library(ke::logger ALIAS ke_logger)
target_include_directories(ke_logger INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ke_logger INTERFACE ke_common)
install(TARGETS ke_logger EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
