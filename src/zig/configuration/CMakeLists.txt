# ke_configuration — kernel primitive, Zig impl behind the C ABI in
# src/c/configuration/include. Mirrors the src/zig/render/webgpu integration:
# a `zig build` custom command produces the DLL, exposed to CMake as a SHARED
# IMPORTED target so C/C++ consumers link it and pick up both headers.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_configuration${CMAKE_SHARED_LIBRARY_SUFFIX}")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-config-include=${CMAKE_SOURCE_DIR}/src/c/configuration/include"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/configuration.zig"
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${CMAKE_SOURCE_DIR}/src/c/configuration/include/kernel_engine/configuration/configuration.h"
        ke_common
    COMMENT "Building ke_configuration (Zig)"
    VERBATIM
)

add_custom_target(ke_configuration_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_configuration_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# ── Imported target ────────────────────────────────────────────────────────────

add_library(ke_configuration SHARED IMPORTED GLOBAL)
add_dependencies(ke_configuration ke_configuration_zig)

set_target_properties(ke_configuration PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/configuration/include"
)

if(WIN32)
    set_target_properties(ke_configuration PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_configuration.lib"
    )
endif()
