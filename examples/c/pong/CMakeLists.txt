cmake_minimum_required(VERSION 3.21)
project(c_pong C)

find_package(KernelEngine REQUIRED CONFIG)

add_executable(c_pong main.c pong.c)
set_target_properties(c_pong PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
target_link_libraries(c_pong PRIVATE
    KernelEngine::ke_window_glfw
    KernelEngine::ke_input_default
    KernelEngine::ke_io_pool
    KernelEngine::ke_file_system_std
    KernelEngine::ke_task_pool_enki
    KernelEngine::ke_ecs_flecs
    KernelEngine::ke_runtime
    KernelEngine::ke_framework
    KernelEngine::ke_configuration
    KernelEngine::ke_configuration_toml
    KernelEngine::ke_audio_miniaudio
    KernelEngine::ke_audio_module
    KernelEngine::ke_text_stb_truetype
    KernelEngine::ke_physics_2d_box2d
    KernelEngine::ke_physics_body2d
    KernelEngine::ke_gpu_device_webgpu
    KernelEngine::ke_render_service
    KernelEngine::ke_render_binder_grouped
    KernelEngine::ke_view_space
    KernelEngine::ke_render_camera
    KernelEngine::ke_render_scene
    KernelEngine::ke_render_frame
    KernelEngine::ke_render_shadow
    KernelEngine::ke_render_cluster
    KernelEngine::ke_render_gbuffer
    KernelEngine::ke_render_deferred_lighting
    KernelEngine::ke_render_forward
    KernelEngine::ke_render_tonemap
    KernelEngine::ke_render_ui)
if(NOT WIN32)
    target_link_libraries(c_pong PRIVATE m)
endif()
