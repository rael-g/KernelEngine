# ke_runtime — the in-house scheduler (Bevy-style waves + enki dispatch + defer
# queue + fixed timestep), built in Zig. Mirrors src/zig/logger/simple's
# zig-build-as-imported-target pattern. Contract headers stay in
# src/c/runtime/include; only the implementation moved to Zig. ke_framework
# depends on the runtime header only (calls ke_system_ctx ops through the
# vtable), so no MSVC C DLL links this Zig import lib — see the
# project-zig-migration-msvc-wall memory note.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_runtime${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")
set(KE_RUNTIME_INCLUDE "${CMAKE_SOURCE_DIR}/src/c/runtime/include")

file(GLOB KE_RUNTIME_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-allocator-include=${CMAKE_SOURCE_DIR}/src/c/allocator/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dke-scheduler-include=${CMAKE_SOURCE_DIR}/src/c/scheduler/include"
        "-Dke-runtime-include=${KE_RUNTIME_INCLUDE}"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_RUNTIME_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
    COMMENT "Building ke_runtime (Zig)"
    VERBATIM
)

add_custom_target(ke_runtime_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_runtime_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_runtime_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_runtime.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_runtime.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_runtime SHARED IMPORTED GLOBAL)
add_dependencies(ke_runtime ke_runtime_zig)

set_target_properties(ke_runtime PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES "${KE_RUNTIME_INCLUDE}"
    INTERFACE_LINK_LIBRARIES "ke_common;ke_allocator;ke_ecs;ke_scheduler"
)

if(WIN32)
    set_target_properties(ke_runtime PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_runtime.lib"
    )
endif()
