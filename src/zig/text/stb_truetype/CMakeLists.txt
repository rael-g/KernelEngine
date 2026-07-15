# ke_text_stb_truetype — the stb_truetype-backed ke_font_loader, its own
# plugin: own factory (ke_font_loader_stb_create), own Zig build. Mirrors
# src/zig/asset/stb_image's zig-build-as-imported-target pattern.

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_path(STB_INCLUDE_DIR "stb_truetype.h" REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_text_stb_truetype${CMAKE_SHARED_LIBRARY_SUFFIX}")

file(GLOB KE_TEXT_STB_TRUETYPE_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dke-text-include=${CMAKE_SOURCE_DIR}/src/c/text/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dstb-include=${STB_INCLUDE_DIR}"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_TEXT_STB_TRUETYPE_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/src/stb_font_impl.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kernel_engine/text/stb_truetype/stb_font.h"
        ke_common
    COMMENT "Building ke_text_stb_truetype (Zig)"
    VERBATIM
)

add_custom_target(ke_text_stb_truetype_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_text_stb_truetype_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/ke_text_stb_truetype.lib"
        "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_text_stb_truetype.lib"
    VERBATIM
)

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_text_stb_truetype SHARED IMPORTED GLOBAL)
add_dependencies(ke_text_stb_truetype ke_text_stb_truetype_zig)

set_target_properties(ke_text_stb_truetype PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/text/include"
)

if(WIN32)
    set_target_properties(ke_text_stb_truetype PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_text_stb_truetype.lib"
    )
endif()
