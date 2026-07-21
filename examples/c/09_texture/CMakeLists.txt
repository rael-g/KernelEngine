find_program(GLSLANG glslangValidator REQUIRED)

set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/shaders")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/tex_vert.h"
    COMMAND "${GLSLANG}" -V -S vert --vn tex_vert_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/tex.vert.glsl"
            -o "${SHADER_GEN_DIR}/tex_vert.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tex.vert.glsl"
    VERBATIM
)

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/tex_frag.h"
    COMMAND "${GLSLANG}" -V -S frag --vn tex_frag_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/tex.frag.glsl"
            -o "${SHADER_GEN_DIR}/tex_frag.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tex.frag.glsl"
    VERBATIM
)

add_custom_target(c_demo_09_shaders DEPENDS
    "${SHADER_GEN_DIR}/tex_vert.h"
    "${SHADER_GEN_DIR}/tex_frag.h"
)

add_executable(c_demo_09 main.c)
add_dependencies(c_demo_09 c_demo_09_shaders)
target_include_directories(c_demo_09 PRIVATE "${SHADER_GEN_DIR}")
target_link_libraries(c_demo_09 PRIVATE
    ke_common
    ke_window
    ke_window_glfw
    ke_gpu_device_webgpu
)
