# ke_input_default — keyboard/mouse state tracker, a kernel built-in in Zig.
# Mirrors src/zig/logger/simple's zig-build-as-imported-target pattern; pure
# logic, so no third-party C is compiled and only ke_common is linked.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_input_default${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")

file(GLOB KE_INPUT_DEFAULT_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-input-include=${CMAKE_SOURCE_DIR}/src/c/input/include"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_INPUT_DEFAULT_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
    COMMENT "Building ke_input_default (Zig)"
    VERBATIM
)

add_custom_target(ke_input_default_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_input_default_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_input_default_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_input_default.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_input_default.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_input_default SHARED IMPORTED GLOBAL)
add_library(ke::input_default ALIAS ke_input_default)
add_dependencies(ke_input_default ke_input_default_zig)

set_target_properties(ke_input_default PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

if(WIN32)
    set_target_properties(ke_input_default PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_input_default.lib"
    )
endif()
