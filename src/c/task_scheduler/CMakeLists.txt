add_library(ke_task_scheduler INTERFACE)
add_library(ke::task_scheduler ALIAS ke_task_scheduler)
target_include_directories(ke_task_scheduler INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ke_task_scheduler INTERFACE ke_common)
install(TARGETS ke_task_scheduler EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
