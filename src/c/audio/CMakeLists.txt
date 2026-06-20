add_library(ke_audio INTERFACE)

target_include_directories(ke_audio INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

target_link_libraries(ke_audio INTERFACE ke_allocator ke_common)

install(TARGETS ke_audio EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
