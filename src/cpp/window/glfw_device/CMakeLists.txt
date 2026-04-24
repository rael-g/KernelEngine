add_library(ke_window_glfw_device STATIC
    src/glfw_window_device.cpp
)

target_link_libraries(ke_window_glfw_device PUBLIC
    ke_window_contract
    glfw
)

target_include_directories(ke_window_glfw_device PRIVATE
    src
)

# Export standard definitions if any
install(TARGETS ke_window_glfw_device EXPORT KernelEngineTargets)
