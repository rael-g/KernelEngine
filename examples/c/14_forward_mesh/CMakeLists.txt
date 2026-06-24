add_executable(c_demo_14 main.c)
target_link_libraries(c_demo_14 PRIVATE
    ke_common
    ke_render
    ke_window_contract
    ke_window_glfw
    ke_gpu_device_webgpu
    ke_render_core
    ke_ecs_flecs
    ke_scheduler_enki
    ke_runtime
)
