add_library(ke_window_core STATIC
    src/window_core.cpp
)

target_link_libraries(ke_window_core PUBLIC
    ke_window_hal
    ke_kernel
)

target_include_directories(ke_window_core PRIVATE
    src
)

install(TARGETS ke_window_core EXPORT KernelEngineTargets)
