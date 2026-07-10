find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(Python3 COMPONENTS Interpreter REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_render_core${CMAKE_SHARED_LIBRARY_SUFFIX}")

# Zig resolves its own compilation unit from the @import graph, so CMake cannot
# know which files matter. Depend on all of them: a source omitted here rebuilds
# nothing and ships a stale binary, which fails silently at runtime.
# CONFIGURE_DEPENDS re-runs the glob when a file is added or removed.
file(GLOB KE_RENDER_CORE_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

# Compile pass shaders (Slang -> WGSL) for @embedFile in the Zig lib.
set(COMPILE_SLANG "${CMAKE_SOURCE_DIR}/scripts/compile_slang.py")
set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")
# One WGSL module per stage: a uniform shared across stages would be declared
# twice (invalid WGSL) if both entry points were emitted into one module.
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/cluster_cull.cs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry cs_main --stage compute
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/cluster_cull.slang"
            --output "${SHADER_GEN_DIR}/cluster_cull.cs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/cluster_cull.slang" "${COMPILE_SLANG}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/magenta.vs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry vs_main --stage vertex
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/magenta.slang"
            --output "${SHADER_GEN_DIR}/magenta.vs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/magenta.slang" "${COMPILE_SLANG}"
    VERBATIM
)
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/magenta.fs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry fs_main --stage fragment
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/magenta.slang"
            --output "${SHADER_GEN_DIR}/magenta.fs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/magenta.slang" "${COMPILE_SLANG}"
    VERBATIM
)

set(KE_SHADER_LIB_DIR "${CMAKE_SOURCE_DIR}/src/shaders")

# Deferred lighting: fullscreen resolve reading the G-buffer + depth, shading
# with the shared shadow/ibl/cluster hooks + ke.pbr. Needs the ke library dir
# (ke.pbr) + the core shaders dir (the feature imports).
# Transparent forward: the same flat material bound into the transparent-only
# forward pass (transparent_forward.slang), the BLEND counterpart to the encode
# pass (gbuffer.slang). Adds refraction_feature.slang to the shared
# shadow/ibl/cluster dependency set.
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/mat_test_flat_transparent.vs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry vs_main --stage vertex
            --include "${KE_SHADER_LIB_DIR}"
            --include "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_test_flat_transparent.slang"
            --output "${SHADER_GEN_DIR}/mat_test_flat_transparent.vs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_test_flat_transparent.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/transparent_forward.slang"
            "${KE_SHADER_LIB_DIR}/forward_common.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/shadow_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/ibl_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/cluster_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/refraction_feature.slang"
            "${KE_SHADER_LIB_DIR}/ke.slang"
            "${KE_SHADER_LIB_DIR}/ke/surface.slang"
            "${KE_SHADER_LIB_DIR}/ke/pbr.slang"
            "${COMPILE_SLANG}"
    VERBATIM
)
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/mat_test_flat_transparent.fs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry fs_main --stage fragment
            --include "${KE_SHADER_LIB_DIR}"
            --include "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_test_flat_transparent.slang"
            --output "${SHADER_GEN_DIR}/mat_test_flat_transparent.fs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/mat_test_flat_transparent.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/transparent_forward.slang"
            "${KE_SHADER_LIB_DIR}/forward_common.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/shadow_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/ibl_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/cluster_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/refraction_feature.slang"
            "${KE_SHADER_LIB_DIR}/ke.slang"
            "${KE_SHADER_LIB_DIR}/ke/surface.slang"
            "${KE_SHADER_LIB_DIR}/ke/pbr.slang"
            "${COMPILE_SLANG}"
    VERBATIM
)

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
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/shadow_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/ibl_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/cluster_feature.slang"
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
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/shadow_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/ibl_feature.slang"
            "${CMAKE_CURRENT_SOURCE_DIR}/shaders/cluster_feature.slang"
            "${KE_SHADER_LIB_DIR}/ke.slang"
            "${KE_SHADER_LIB_DIR}/ke/surface.slang"
            "${KE_SHADER_LIB_DIR}/ke/pbr.slang"
            "${COMPILE_SLANG}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}" "${ZIG_OUT_DIR}/lib/ke_render_core.lib"
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
        "-Dke-tonemap-include=${CMAKE_SOURCE_DIR}/src/zig/render/tonemap/include"
        "-Dke-skybox-include=${CMAKE_SOURCE_DIR}/src/zig/render/skybox/include"
        "-Dke-ui-include=${CMAKE_SOURCE_DIR}/src/zig/render/ui/include"
        "-Dke-gbuffer-include=${CMAKE_SOURCE_DIR}/src/zig/render/gbuffer/include"
        "-Dke-shadow-include=${CMAKE_SOURCE_DIR}/src/zig/render/shadow/include"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "-Dcluster-cull-cs-wgsl=${SHADER_GEN_DIR}/cluster_cull.cs.wgsl"
        "-Dmat-test-flat-transparent-vs-wgsl=${SHADER_GEN_DIR}/mat_test_flat_transparent.vs.wgsl"
        "-Dmat-test-flat-transparent-fs-wgsl=${SHADER_GEN_DIR}/mat_test_flat_transparent.fs.wgsl"
        "-Ddeferred-lighting-vs-wgsl=${SHADER_GEN_DIR}/deferred_lighting.vs.wgsl"
        "-Ddeferred-lighting-fs-wgsl=${SHADER_GEN_DIR}/deferred_lighting.fs.wgsl"
        "-Dmagenta-vs-wgsl=${SHADER_GEN_DIR}/magenta.vs.wgsl"
        "-Dmagenta-fs-wgsl=${SHADER_GEN_DIR}/magenta.fs.wgsl"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        # Every Zig source, not a hand-listed subset: a stale binary from an
        # unlisted file is silent and costs far more than an occasional rebuild.
        ${KE_RENDER_CORE_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${SHADER_GEN_DIR}/cluster_cull.cs.wgsl"
        "${SHADER_GEN_DIR}/mat_test_flat_transparent.vs.wgsl"
        "${SHADER_GEN_DIR}/mat_test_flat_transparent.fs.wgsl"
        "${SHADER_GEN_DIR}/deferred_lighting.vs.wgsl"
        "${SHADER_GEN_DIR}/deferred_lighting.fs.wgsl"
        "${SHADER_GEN_DIR}/magenta.vs.wgsl"
        "${SHADER_GEN_DIR}/magenta.fs.wgsl"
        ke_common
        ke_runtime
        ke_render_tonemap_zig
        ke_render_skybox_zig
        ke_render_ui_zig
        ke_render_gbuffer_zig
        ke_render_shadow_zig
    VERBATIM
)

add_custom_target(ke_render_core_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_render_core_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

add_library(ke_render_core SHARED IMPORTED GLOBAL)
add_dependencies(ke_render_core ke_render_core_zig)

set_target_properties(ke_render_core PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/render/include"
)

if(WIN32)
    set_target_properties(ke_render_core PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_render_core.lib"
    )
endif()
