# ke_common — the engine's error vocabulary, a kernel built-in built in Zig.
# Mirrors src/zig/logger/simple's zig-build-as-imported-target pattern. The
# public headers under include/ stay C; only the implementation is Zig, and the
# heap-owned error copies go straight to libc malloc/free (no allocator link).
#
# Unlike the other built-ins this one exports data symbols (the KE_ERROR_* type
# singletons) as well as functions, and carries the public common headers that
# nearly every other target consumes.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_common${CMAKE_SHARED_LIBRARY_SUFFIX}")

file(GLOB KE_COMMON_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_COMMON_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
    COMMENT "Building ke_common (Zig)"
    VERBATIM
)

add_custom_target(ke_common_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_common_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_common_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_common.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_common.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_common SHARED IMPORTED GLOBAL)
add_library(ke::common ALIAS ke_common)
add_dependencies(ke_common ke_common_zig)

set_target_properties(ke_common PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

if(WIN32)
    set_target_properties(ke_common PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_common.lib"
    )
endif()

install(DIRECTORY include/ DESTINATION include)
