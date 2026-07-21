find_program(GLSLANG glslangValidator REQUIRED)

set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/shaders")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/mesh_vert.h"
    COMMAND "${GLSLANG}" -V -S vert --vn mesh_vert_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/mesh.vert.glsl"
            -o "${SHADER_GEN_DIR}/mesh_vert.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/mesh.vert.glsl"
    VERBATIM
)

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/mesh_frag.h"
    COMMAND "${GLSLANG}" -V -S frag --vn mesh_frag_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/mesh.frag.glsl"
            -o "${SHADER_GEN_DIR}/mesh_frag.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/mesh.frag.glsl"
    VERBATIM
)

add_custom_target(c_demo_08_shaders DEPENDS
    "${SHADER_GEN_DIR}/mesh_vert.h"
    "${SHADER_GEN_DIR}/mesh_frag.h"
)

add_executable(c_demo_08 main.c)
add_dependencies(c_demo_08 c_demo_08_shaders)
target_include_directories(c_demo_08 PRIVATE "${SHADER_GEN_DIR}")
target_link_libraries(c_demo_08 PRIVATE
    ke_common
    ke_window
    ke_window_glfw
    ke_gpu_device_webgpu
)
