# ke_render_deferred_lighting — the opaque path's second half render pass, its
# own plugin: own factory (ke_render_deferred_lighting_create), own shader,
# own Zig build. Talks to the rest of the pipeline only through the borrowed
# ke_runtime/ke_render_core/ke_gpu_device handles passed to the factory, plus
# shadow/cluster's outputs looked up by name through ke_render_core. Mirrors
# ke_render_gbuffer's build shape (see that CMakeLists.txt for the base
# pattern); the shader side needs the shared ke library dir (ke.slang,
# gbuffer_encoding.slang, shadow_feature.slang, ibl_feature.slang,
# cluster_feature.slang) since deferred_lighting.slang imports them.

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(Python3 COMPONENTS Interpreter REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_render_deferred_lighting${CMAKE_SHARED_LIBRARY_SUFFIX}")

set(COMPILE_SLANG "${CMAKE_SOURCE_DIR}/scripts/compile_slang.py")
set(KE_SHADER_LIB_DIR "${CMAKE_SOURCE_DIR}/src/shaders")
set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/deferred_lighting.vs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry vs_main --stage vertex
            --include "${KE_SHADER_LIB_DIR}"
            --include "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/deferred_lighting.slang"
            --output "${SHADER_GEN_DIR}/deferred_lighting.vs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/deferred_lighting.slang"
            "${KE_SHADER_LIB_DIR}/gbuffer_encoding.slang"
            "${KE_SHADER_LIB_DIR}/shadow_feature.slang"
            "${KE_SHADER_LIB_DIR}/ibl_feature.slang"
            "${KE_SHADER_LIB_DIR}/cluster_feature.slang"
            "${KE_SHADER_LIB_DIR}/ke.slang"
            "${KE_SHADER_LIB_DIR}/ke/surface.slang"
            "${KE_SHADER_LIB_DIR}/ke/pbr.slang"
            "${COMPILE_SLANG}"
    VERBATIM
)
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/deferred_lighting.fs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry fs_main --stage fragment
            --include "${KE_SHADER_LIB_DIR}"
            --include "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/deferred_lighting.slang"
            --output "${SHADER_GEN_DIR}/deferred_lighting.fs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/deferred_lighting.slang"
            "${KE_SHADER_LIB_DIR}/gbuffer_encoding.slang"
            "${KE_SHADER_LIB_DIR}/shadow_feature.slang"
            "${KE_SHADER_LIB_DIR}/ibl_feature.slang"
            "${KE_SHADER_LIB_DIR}/cluster_feature.slang"
            "${KE_SHADER_LIB_DIR}/ke.slang"
            "${KE_SHADER_LIB_DIR}/ke/surface.slang"
            "${KE_SHADER_LIB_DIR}/ke/pbr.slang"
            "${COMPILE_SLANG}"
    VERBATIM
)

file(GLOB KE_RENDER_DEFERRED_LIGHTING_ZIG_SOURCES CONFIGURE_DEPENDS
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
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "-Ddeferred-lighting-vs-wgsl=${SHADER_GEN_DIR}/deferred_lighting.vs.wgsl"
        "-Ddeferred-lighting-fs-wgsl=${SHADER_GEN_DIR}/deferred_lighting.fs.wgsl"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_RENDER_DEFERRED_LIGHTING_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${SHADER_GEN_DIR}/deferred_lighting.vs.wgsl"
        "${SHADER_GEN_DIR}/deferred_lighting.fs.wgsl"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kernel_engine/render/deferred_lighting/deferred_lighting_create.h"
        ke_common
    COMMENT "Building ke_render_deferred_lighting (Zig)"
    VERBATIM
)

add_custom_target(ke_render_deferred_lighting_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_render_deferred_lighting_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/ke_render_deferred_lighting.lib"
        "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_render_deferred_lighting.lib"
    VERBATIM
)

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_render_deferred_lighting SHARED IMPORTED GLOBAL)
add_dependencies(ke_render_deferred_lighting ke_render_deferred_lighting_zig)

set_target_properties(ke_render_deferred_lighting PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/render/include"
)

if(WIN32)
    set_target_properties(ke_render_deferred_lighting PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_render_deferred_lighting.lib"
    )
endif()
