# ke_render_ui — the UI overlay render pass, its own plugin: own factory
# (ke_render_ui_create), own shader, own Zig build. Unlike tonemap/skybox
# (fire-and-forget), this plugin exposes a real vtable (ke_render_ui.ui_quad)
# since game code queues quads into it at runtime. Mirrors ke_render_tonemap's
# build shape (see that CMakeLists.txt for the base pattern).

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(Python3 COMPONENTS Interpreter REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_render_ui${CMAKE_SHARED_LIBRARY_SUFFIX}")

set(COMPILE_SLANG "${CMAKE_SOURCE_DIR}/scripts/compile_slang.py")
set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")

add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/ui.vs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry vs_main --stage vertex
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/ui.slang"
            --output "${SHADER_GEN_DIR}/ui.vs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/ui.slang" "${COMPILE_SLANG}"
    VERBATIM
)
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/ui.fs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry fs_main --stage fragment
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/ui.slang"
            --output "${SHADER_GEN_DIR}/ui.fs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/ui.slang" "${COMPILE_SLANG}"
    VERBATIM
)

file(GLOB KE_RENDER_UI_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-allocator-include=${CMAKE_SOURCE_DIR}/src/c/allocator/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dke-runtime-include=${CMAKE_SOURCE_DIR}/src/c/runtime/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "-Dui-vs-wgsl=${SHADER_GEN_DIR}/ui.vs.wgsl"
        "-Dui-fs-wgsl=${SHADER_GEN_DIR}/ui.fs.wgsl"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_RENDER_UI_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${SHADER_GEN_DIR}/ui.vs.wgsl"
        "${SHADER_GEN_DIR}/ui.fs.wgsl"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kernel_engine/render/ui/ui_create.h"
        ke_common
    COMMENT "Building ke_render_ui (Zig)"
    VERBATIM
)

add_custom_target(ke_render_ui_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_render_ui_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/ke_render_ui.lib"
        "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_render_ui.lib"
    VERBATIM
)

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_render_ui SHARED IMPORTED GLOBAL)
add_dependencies(ke_render_ui ke_render_ui_zig)

set_target_properties(ke_render_ui PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/render/include"
)

if(WIN32)
    set_target_properties(ke_render_ui PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_render_ui.lib"
    )
endif()
