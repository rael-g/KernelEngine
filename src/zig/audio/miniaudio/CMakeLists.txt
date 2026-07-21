# ke_audio_miniaudio — the miniaudio-backed ke_audio, its own plugin: own
# factory (ke_audio_miniaudio_create), own Zig build. Mirrors
# src/zig/asset/stb_image's zig-build-as-imported-target pattern.

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_path(MINIAUDIO_INCLUDE_DIR "miniaudio.h" REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_audio_miniaudio${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")

file(GLOB KE_AUDIO_MINIAUDIO_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dke-audio-include=${CMAKE_SOURCE_DIR}/src/c/audio/include"
        "-Dke-resource-cache-include=${CMAKE_SOURCE_DIR}/src/c/resource_cache/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dminiaudio-include=${MINIAUDIO_INCLUDE_DIR}"
        "-Dke-resource-cache-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_resource_cache_default>"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_AUDIO_MINIAUDIO_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/src/miniaudio_impl.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kernel_engine/audio/miniaudio/miniaudio_audio.h"
        ke_resource_cache_default
    COMMENT "Building ke_audio_miniaudio (Zig)"
    VERBATIM
)

add_custom_target(ke_audio_miniaudio_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_audio_miniaudio_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_audio_miniaudio_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_audio_miniaudio.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_audio_miniaudio.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_audio_miniaudio SHARED IMPORTED GLOBAL)
add_dependencies(ke_audio_miniaudio ke_audio_miniaudio_zig)

set_target_properties(ke_audio_miniaudio PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/audio/include"
)

if(WIN32)
    set_target_properties(ke_audio_miniaudio PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_audio_miniaudio.lib"
    )
endif()
