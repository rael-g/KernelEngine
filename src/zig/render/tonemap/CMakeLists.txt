# ke_render_tonemap — the ACES tonemap render pass, its own plugin: own
# factory (ke_render_tonemap_create), own shader, own Zig build. Talks to the
# rest of the pipeline only through the borrowed ke_runtime/ke_render_core/
# ke_gpu_device handles passed to the factory — never links ke_render_core's
# Zig sources. Mirrors src/zig/configuration's zig-build-as-imported-target
# pattern (see that CMakeLists.txt for the base shape).

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_render_tonemap${CMAKE_SHARED_LIBRARY_SUFFIX}")

# Compiled to the shared runtime shaders directory (not embedded into this
# plugin's DLL) — the pass loads them at runtime by logical name via
# ke_render_core::load_shader, so this plugin never names a shader format.
ke_compile_slang_shader(
    NAME tonemap STAGE vertex ENTRY vs_main
    INPUT "${CMAKE_CURRENT_SOURCE_DIR}/shaders/tonemap.slang"
    OUT_FILE tonemap_vs_out
)
ke_compile_slang_shader(
    NAME tonemap STAGE fragment ENTRY fs_main
    INPUT "${CMAKE_CURRENT_SOURCE_DIR}/shaders/tonemap.slang"
    OUT_FILE tonemap_fs_out
)
add_custom_target(ke_render_tonemap_shaders ALL DEPENDS "${tonemap_vs_out}" "${tonemap_fs_out}")

file(GLOB KE_RENDER_TONEMAP_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dke-runtime-include=${CMAKE_SOURCE_DIR}/src/c/runtime/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dke-lib-dir=${CMAKE_RUNTIME_OUTPUT_DIRECTORY}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_RENDER_TONEMAP_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kernel_engine/render/tonemap/tonemap_create.h"
        ke_common
    COMMENT "Building ke_render_tonemap (Zig)"
    VERBATIM
)

add_custom_target(ke_render_tonemap_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_render_tonemap_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# The import library is a Windows-only artifact. Consumers link this
# plugin through the shared archive-output dir; elsewhere the shared
# object itself is the linker input and no separate lib is produced.
if(WIN32)
    add_custom_command(TARGET ke_render_tonemap_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_render_tonemap.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_render_tonemap.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_render_tonemap SHARED IMPORTED GLOBAL)
add_dependencies(ke_render_tonemap ke_render_tonemap_zig)

set_target_properties(ke_render_tonemap PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/render/include"
)

if(WIN32)
    set_target_properties(ke_render_tonemap PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_render_tonemap.lib"
    )
endif()
