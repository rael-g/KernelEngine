add_library(ke_window_core STATIC
    src/window_core.cpp
)

target_link_libraries(ke_window_core PUBLIC
    ke_window_contract
    ke_input
    ke_window
    ke_allocator
    ke_logger
)

target_include_directories(ke_window_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_include_directories(ke_window_core PRIVATE
    src
)

install(TARGETS ke_window_core EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
