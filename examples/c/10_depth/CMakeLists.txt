find_program(GLSLANG glslangValidator REQUIRED)

set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/shaders")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/depth_vert.h"
    COMMAND "${GLSLANG}" -V -S vert --vn depth_vert_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/depth.vert.glsl"
            -o "${SHADER_GEN_DIR}/depth_vert.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/depth.vert.glsl"
    VERBATIM
)

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/depth_frag.h"
    COMMAND "${GLSLANG}" -V -S frag --vn depth_frag_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/depth.frag.glsl"
            -o "${SHADER_GEN_DIR}/depth_frag.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/depth.frag.glsl"
    VERBATIM
)

add_custom_target(c_demo_10_shaders DEPENDS
    "${SHADER_GEN_DIR}/depth_vert.h"
    "${SHADER_GEN_DIR}/depth_frag.h"
)

add_executable(c_demo_10 main.c)
add_dependencies(c_demo_10 c_demo_10_shaders)
target_include_directories(c_demo_10 PRIVATE "${SHADER_GEN_DIR}")
target_link_libraries(c_demo_10 PRIVATE
    ke_common
    ke_window
    ke_window_glfw
    ke_gpu_device_webgpu
)
