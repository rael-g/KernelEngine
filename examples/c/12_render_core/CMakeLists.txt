find_package(Python3 COMPONENTS Interpreter REQUIRED)
set(COMPILE_SLANG "${CMAKE_SOURCE_DIR}/scripts/compile_slang.py")

set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/shaders")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/triangle_wgsl.h"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/triangle.slang"
            --output "${SHADER_GEN_DIR}/triangle_wgsl.h"
            --name   triangle_wgsl
            --target wgsl
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/triangle.slang" "${COMPILE_SLANG}"
    VERBATIM
)

add_custom_target(c_demo_12_shaders DEPENDS
    "${SHADER_GEN_DIR}/triangle_wgsl.h"
)

add_executable(c_demo_12 main.c)
add_dependencies(c_demo_12 c_demo_12_shaders)
target_include_directories(c_demo_12 PRIVATE "${SHADER_GEN_DIR}")
target_link_libraries(c_demo_12 PRIVATE
    ke_common
    ke_window
    ke_window_glfw
    ke_gpu_device_webgpu
    ke_render_core
    ke_ecs_flecs
)
