add_executable(c_demo_05 main.c)

target_link_libraries(c_demo_05 PRIVATE
    ke_common
    ke_gpu_device_webgpu
)
