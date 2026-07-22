# ke_framework — the engine's composition layer (world, scene tree, scene
# loader, asset resolver, input actions), built by Zig.
#
# Mirrors src/zig/runtime's zig-build-as-imported-target shape.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_framework${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")

file(GLOB_RECURSE KE_FRAMEWORK_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dke-spatial-include=${CMAKE_SOURCE_DIR}/src/c/spatial/include"
        "-Dke-input-include=${CMAKE_SOURCE_DIR}/src/c/input/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-asset-include=${CMAKE_SOURCE_DIR}/src/c/asset/include"
        "-Dke-text-include=${CMAKE_SOURCE_DIR}/src/c/text/include"
        "-Dke-runtime-include=${CMAKE_SOURCE_DIR}/src/c/runtime/include"
        "-Dke-scheduler-include=${CMAKE_SOURCE_DIR}/src/c/scheduler/include"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_FRAMEWORK_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
    COMMENT "Building ke_framework (Zig)"
    VERBATIM
)

add_custom_target(ke_framework_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_framework_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_framework_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_framework.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_framework.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_framework SHARED IMPORTED GLOBAL)
add_dependencies(ke_framework ke_framework_zig)

set_target_properties(ke_framework PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/runtime/include"
    INTERFACE_LINK_LIBRARIES
        "ke_common"
)

if(WIN32)
    set_target_properties(ke_framework PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_framework.lib"
    )
endif()
