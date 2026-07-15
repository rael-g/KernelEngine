# ke_resource_cache_default — generic refcount + path-dedup cache, a kernel
# built-in in Zig. Mirrors src/zig/logger/simple's zig-build-as-imported-target
# pattern; pure logic, so no third-party C is compiled and only ke_common is
# linked.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_resource_cache_default${CMAKE_SHARED_LIBRARY_SUFFIX}")

file(GLOB KE_RESOURCE_CACHE_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-resource-cache-include=${CMAKE_SOURCE_DIR}/src/c/resource_cache/include"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_RESOURCE_CACHE_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        ke_common
    COMMENT "Building ke_resource_cache_default (Zig)"
    VERBATIM
)

add_custom_target(ke_resource_cache_default_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_resource_cache_default_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/ke_resource_cache_default.lib"
        "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_resource_cache_default.lib"
    VERBATIM
)

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_resource_cache_default SHARED IMPORTED GLOBAL)
add_library(ke::resource_cache_default ALIAS ke_resource_cache_default)
add_dependencies(ke_resource_cache_default ke_resource_cache_default_zig)

set_target_properties(ke_resource_cache_default PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_LINK_LIBRARIES "ke_resource_cache"
)

if(WIN32)
    set_target_properties(ke_resource_cache_default PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_resource_cache_default.lib"
    )
endif()
