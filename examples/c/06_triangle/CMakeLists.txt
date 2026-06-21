find_program(GLSLANG glslangValidator REQUIRED)

set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/shaders")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/triangle_vert.h"
    COMMAND "${GLSLANG}" -V -S vert --vn triangle_vert_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/triangle.vert.glsl"
            -o "${SHADER_GEN_DIR}/triangle_vert.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/triangle.vert.glsl"
    VERBATIM
)

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/triangle_frag.h"
    COMMAND "${GLSLANG}" -V -S frag --vn triangle_frag_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/triangle.frag.glsl"
            -o "${SHADER_GEN_DIR}/triangle_frag.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/triangle.frag.glsl"
    VERBATIM
)

add_custom_target(c_demo_06_shaders DEPENDS
    "${SHADER_GEN_DIR}/triangle_vert.h"
    "${SHADER_GEN_DIR}/triangle_frag.h"
)

add_executable(c_demo_06 main.c)
add_dependencies(c_demo_06 c_demo_06_shaders)
target_include_directories(c_demo_06 PRIVATE "${SHADER_GEN_DIR}")
target_link_libraries(c_demo_06 PRIVATE
    ke_common
    ke_window_contract
    ke_window_glfw
    ke_gpu_device_webgpu
)
