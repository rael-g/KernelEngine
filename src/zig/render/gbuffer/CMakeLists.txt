# ke_render_gbuffer — the deferred G-buffer encode render pass, its own
# plugin: own factory (ke_render_gbuffer_create), own shader, own Zig build.
# Talks to the rest of the pipeline only through the borrowed
# ke_runtime/ke_render_core/ke_gpu_device handles passed to the factory.
# Mirrors ke_render_tonemap's build shape (see that CMakeLists.txt for the
# base pattern); the shader side needs the shared ke library dir (ke.slang,
# forward_common.slang, gbuffer_encoding.slang) since gbuffer.slang imports them.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_render_gbuffer${CMAKE_SHARED_LIBRARY_SUFFIX}")

set(KE_SHADER_LIB_DIR "${CMAKE_SOURCE_DIR}/src/shaders")
set(GBUFFER_SHADER_DEPS
    "${CMAKE_CURRENT_SOURCE_DIR}/shaders/gbuffer.slang"
    "${KE_SHADER_LIB_DIR}/gbuffer_encoding.slang"
    "${KE_SHADER_LIB_DIR}/forward_common.slang"
    "${KE_SHADER_LIB_DIR}/ke.slang"
    "${KE_SHADER_LIB_DIR}/ke/surface.slang"
)

# Every authored material x this pass. The pass hardcodes no material: each
# lands as <material>.gbuffer.{vs,fs}.<ext> in the shared runtime shaders dir,
# resolved by logical name at draw time via ke_render_core::load_shader once a
# material says which shader it wants. Adding a material means dropping a
# .slang in KE_MATERIALS_DIR — this file does not change.
ke_compile_material_shaders(
    PASS gbuffer
    TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/shaders/gbuffer_material.slang.in"
    INCLUDES "${KE_SHADER_LIB_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
    EXTRA_DEPENDS ${GBUFFER_SHADER_DEPS}
    OUT_FILES gbuffer_material_outs
)
add_custom_target(ke_render_gbuffer_shaders ALL DEPENDS ${gbuffer_material_outs})

file(GLOB KE_RENDER_GBUFFER_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dke-runtime-include=${CMAKE_SOURCE_DIR}/src/c/runtime/include"
        "-Dke-spatial-include=${CMAKE_SOURCE_DIR}/src/c/spatial/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dke-lib-dir=${CMAKE_RUNTIME_OUTPUT_DIRECTORY}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_RENDER_GBUFFER_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
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
    VERBATIM
)

# The import library is a Windows-only artifact. Consumers link this
# plugin through the shared archive-output dir; elsewhere the shared
# object itself is the linker input and no separate lib is produced.
if(WIN32)
    add_custom_command(TARGET ke_render_gbuffer_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_render_gbuffer.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_render_gbuffer.lib"
        VERBATIM
    )
endif()

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
