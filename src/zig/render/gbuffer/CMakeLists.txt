# ke_render_gbuffer — the deferred G-buffer encode render pass, its own
# plugin: own factory (ke_render_gbuffer_create), own shader, own Zig build.
# Talks to the rest of the pipeline only through the borrowed
# ke_runtime/ke_render_core/ke_gpu_device handles passed to the factory.
# Mirrors ke_render_tonemap's build shape (see that CMakeLists.txt for the
# base pattern); the shader side needs the shared ke library dir (ke.slang,
# forward_common.slang, gbuffer_encoding.slang) since gbuffer.slang imports them.

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(Python3 COMPONENTS Interpreter REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_render_gbuffer${CMAKE_SHARED_LIBRARY_SUFFIX}")

set(COMPILE_SLANG "${CMAKE_SOURCE_DIR}/scripts/compile_slang.py")
set(KE_SHADER_LIB_DIR "${CMAKE_SOURCE_DIR}/src/shaders")
set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/mat_test_flat_gbuffer.vs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry vs_main --stage vertex
            --include "${KE_SHADER_LIB_DIR}"
            --include "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_test_flat_gbuffer.slang"
            --output "${SHADER_GEN_DIR}/mat_test_flat_gbuffer.vs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_test_flat_gbuffer.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/gbuffer.slang"
            "${KE_SHADER_LIB_DIR}/gbuffer_encoding.slang"
            "${KE_SHADER_LIB_DIR}/forward_common.slang"
            "${KE_SHADER_LIB_DIR}/ke.slang"
            "${KE_SHADER_LIB_DIR}/ke/surface.slang"
            "${COMPILE_SLANG}"
    VERBATIM
)
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/mat_test_flat_gbuffer.fs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry fs_main --stage fragment
            --include "${KE_SHADER_LIB_DIR}"
            --include "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_test_flat_gbuffer.slang"
            --output "${SHADER_GEN_DIR}/mat_test_flat_gbuffer.fs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_test_flat_gbuffer.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/gbuffer.slang"
            "${KE_SHADER_LIB_DIR}/gbuffer_encoding.slang"
            "${KE_SHADER_LIB_DIR}/forward_common.slang"
            "${KE_SHADER_LIB_DIR}/ke.slang"
            "${KE_SHADER_LIB_DIR}/ke/surface.slang"
            "${COMPILE_SLANG}"
    VERBATIM
)

# Second built-in material (§6 Mechanism 1 proof — a distinct shader, not just
# distinct data, must resolve to a distinct PSO through the render core's
# get_or_create_pipeline cache). Mirrors the mat_test_flat_gbuffer pair above.
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/mat_stripes_gbuffer.vs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry vs_main --stage vertex
            --include "${KE_SHADER_LIB_DIR}"
            --include "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_stripes_gbuffer.slang"
            --output "${SHADER_GEN_DIR}/mat_stripes_gbuffer.vs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_stripes_gbuffer.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/gbuffer.slang"
            "${KE_SHADER_LIB_DIR}/gbuffer_encoding.slang"
            "${KE_SHADER_LIB_DIR}/forward_common.slang"
            "${KE_SHADER_LIB_DIR}/ke.slang"
            "${KE_SHADER_LIB_DIR}/ke/surface.slang"
            "${COMPILE_SLANG}"
    VERBATIM
)
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/mat_stripes_gbuffer.fs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry fs_main --stage fragment
            --include "${KE_SHADER_LIB_DIR}"
            --include "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_stripes_gbuffer.slang"
            --output "${SHADER_GEN_DIR}/mat_stripes_gbuffer.fs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_stripes_gbuffer.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/gbuffer.slang"
            "${KE_SHADER_LIB_DIR}/gbuffer_encoding.slang"
            "${KE_SHADER_LIB_DIR}/forward_common.slang"
            "${KE_SHADER_LIB_DIR}/ke.slang"
            "${KE_SHADER_LIB_DIR}/ke/surface.slang"
            "${COMPILE_SLANG}"
    VERBATIM
)

file(GLOB KE_RENDER_GBUFFER_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-allocator-include=${CMAKE_SOURCE_DIR}/src/c/allocator/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dke-runtime-include=${CMAKE_SOURCE_DIR}/src/c/runtime/include"
        "-Dke-spatial-include=${CMAKE_SOURCE_DIR}/src/c/spatial/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "-Dgbuffer-vs-wgsl=${SHADER_GEN_DIR}/mat_test_flat_gbuffer.vs.wgsl"
        "-Dgbuffer-fs-wgsl=${SHADER_GEN_DIR}/mat_test_flat_gbuffer.fs.wgsl"
        "-Dstripes-vs-wgsl=${SHADER_GEN_DIR}/mat_stripes_gbuffer.vs.wgsl"
        "-Dstripes-fs-wgsl=${SHADER_GEN_DIR}/mat_stripes_gbuffer.fs.wgsl"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_RENDER_GBUFFER_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${SHADER_GEN_DIR}/mat_test_flat_gbuffer.vs.wgsl"
        "${SHADER_GEN_DIR}/mat_test_flat_gbuffer.fs.wgsl"
        "${SHADER_GEN_DIR}/mat_stripes_gbuffer.vs.wgsl"
        "${SHADER_GEN_DIR}/mat_stripes_gbuffer.fs.wgsl"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kernel_engine/render/gbuffer/gbuffer_create.h"
        ke_common
    COMMENT "Building ke_render_gbuffer (Zig)"
    VERBATIM
)

add_custom_target(ke_render_gbuffer_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_render_gbuffer_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/ke_render_gbuffer.lib"
        "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_render_gbuffer.lib"
    VERBATIM
)

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_render_gbuffer SHARED IMPORTED GLOBAL)
add_dependencies(ke_render_gbuffer ke_render_gbuffer_zig)

set_target_properties(ke_render_gbuffer PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/render/include"
)

if(WIN32)
    set_target_properties(ke_render_gbuffer PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_render_gbuffer.lib"
    )
endif()
