# ke_asset_stb_image — the stb_image-backed ke_image_loader, its own plugin:
# own factory (ke_image_loader_stb_create), own Zig build. Mirrors
# src/zig/render/tonemap's zig-build-as-imported-target pattern (see that
# CMakeLists.txt for the base shape).

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_path(STB_INCLUDE_DIR "stb_image.h" REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_asset_stb_image${CMAKE_SHARED_LIBRARY_SUFFIX}")

file(GLOB KE_ASSET_STB_IMAGE_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-asset-include=${CMAKE_SOURCE_DIR}/src/c/asset/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dstb-include=${STB_INCLUDE_DIR}"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_ASSET_STB_IMAGE_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/src/stb_image_impl.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kernel_engine/asset/stb_image/stb_image_loader.h"
        ke_common
    COMMENT "Building ke_asset_stb_image (Zig)"
    VERBATIM
)

add_custom_target(ke_asset_stb_image_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_asset_stb_image_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/ke_asset_stb_image.lib"
        "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_asset_stb_image.lib"
    VERBATIM
)

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_asset_stb_image SHARED IMPORTED GLOBAL)
add_dependencies(ke_asset_stb_image ke_asset_stb_image_zig)

set_target_properties(ke_asset_stb_image PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/asset/include"
)

if(WIN32)
    set_target_properties(ke_asset_stb_image PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_asset_stb_image.lib"
    )
endif()
