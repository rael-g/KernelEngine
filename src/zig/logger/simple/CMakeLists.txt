# ke_logger_simple — the multi-sink logger, a kernel built-in built in Zig.
# Mirrors src/zig/asset/stb_image's zig-build-as-imported-target pattern; pure
# logic, no third-party C, and no ke_common LINK — errors translate to the C
# ABI at the export seam via the shared Zig kerror utility.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_logger_simple${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")

file(GLOB KE_LOGGER_SIMPLE_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_LOGGER_SIMPLE_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
    COMMENT "Building ke_logger_simple (Zig)"
    VERBATIM
)

add_custom_target(ke_logger_simple_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_logger_simple_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/ke_logger_simple.lib"
        "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_logger_simple.lib"
    VERBATIM
)

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_logger_simple SHARED IMPORTED GLOBAL)
add_library(ke::logger_simple ALIAS ke_logger_simple)
add_dependencies(ke_logger_simple ke_logger_simple_zig)

set_target_properties(ke_logger_simple PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_LINK_LIBRARIES "ke_logger"
)

if(WIN32)
    set_target_properties(ke_logger_simple PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_logger_simple.lib"
    )
endif()
