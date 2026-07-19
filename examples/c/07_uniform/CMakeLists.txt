find_program(GLSLANG glslangValidator REQUIRED)

set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/shaders")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/rotate_vert.h"
    COMMAND "${GLSLANG}" -V -S vert --vn rotate_vert_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/rotate.vert.glsl"
            -o "${SHADER_GEN_DIR}/rotate_vert.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/rotate.vert.glsl"
    VERBATIM
)

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/rotate_frag.h"
    COMMAND "${GLSLANG}" -V -S frag --vn rotate_frag_spv
            "${CMAKE_CURRENT_SOURCE_DIR}/rotate.frag.glsl"
            -o "${SHADER_GEN_DIR}/rotate_frag.h"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/rotate.frag.glsl"
    VERBATIM
)

add_custom_target(c_demo_07_shaders DEPENDS
    "${SHADER_GEN_DIR}/rotate_vert.h"
    "${SHADER_GEN_DIR}/rotate_frag.h"
)

add_executable(c_demo_07 main.c)
add_dependencies(c_demo_07 c_demo_07_shaders)
target_include_directories(c_demo_07 PRIVATE "${SHADER_GEN_DIR}")
target_link_libraries(c_demo_07 PRIVATE
    ke_common
    ke_window_contract
    ke_window_glfw
    ke_gpu_device_webgpu
)

# The math functions live in a separate library on Unix; on Windows they are
# part of the C runtime and need no explicit link.
if(NOT WIN32)
    target_link_libraries(c_demo_07 PRIVATE m)
endif()
