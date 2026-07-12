# ke_render_cluster — the clustered-light-cull compute pass, its own plugin:
# own factory (ke_render_cluster_create), own shader, own Zig build. Talks to
# the rest of the pipeline only through the borrowed ke_runtime/
# ke_render_core/ke_gpu_device handles passed to the factory, publishing its
# outputs ("cluster_lights" bind group + layout, "light_clusters" ordering
# tag) through the named-resource table rather than a vtable. Mirrors
# ke_render_tonemap's build shape.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_render_cluster${CMAKE_SHARED_LIBRARY_SUFFIX}")

# Compiled to the shared runtime shaders directory (not embedded into this
# plugin's DLL) — the pass loads it at runtime by logical name via
# ke_render_core::load_shader, so this plugin never names a shader format.
ke_compile_slang_shader(
    NAME cluster_cull STAGE compute ENTRY cs_main
    INPUT "${CMAKE_CURRENT_SOURCE_DIR}/shaders/cluster_cull.slang"
    OUT_FILE cluster_cull_cs_out
)
add_custom_target(ke_render_cluster_shaders ALL DEPENDS "${cluster_cull_cs_out}")

file(GLOB KE_RENDER_CLUSTER_ZIG_SOURCES CONFIGURE_DEPENDS
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
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_RENDER_CLUSTER_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kernel_engine/render/cluster/cluster_create.h"
        ke_common
    COMMENT "Building ke_render_cluster (Zig)"
    VERBATIM
)

add_custom_target(ke_render_cluster_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_render_cluster_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/ke_render_cluster.lib"
        "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_render_cluster.lib"
    VERBATIM
)

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_render_cluster SHARED IMPORTED GLOBAL)
add_dependencies(ke_render_cluster ke_render_cluster_zig)

set_target_properties(ke_render_cluster PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/render/include"
)

if(WIN32)
    set_target_properties(ke_render_cluster PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_render_cluster.lib"
    )
endif()
