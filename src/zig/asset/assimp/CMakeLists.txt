# ke_asset_assimp — model loading via Assimp, built in Zig.
# Mirrors src/zig/physics/box2d's zig-build-as-imported-target pattern: the
# plugin talks to Assimp through its C API, so nothing here needs a C++
# compiler even though Assimp itself is C++.

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(assimp CONFIG REQUIRED)
find_path(STB_INCLUDE_DIR "stb_image.h" REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_asset_assimp${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")

get_target_property(ASSIMP_INCLUDE_DIRS assimp::assimp INTERFACE_INCLUDE_DIRECTORIES)
list(GET ASSIMP_INCLUDE_DIRS 0 ASSIMP_INCLUDE_DIR)

# Assimp is a static library with a dependency chain of its own (pugixml,
# poly2tri, minizip, zlib...). Zig links archives by path, so CMake resolves
# each of those targets to its file here and passes the whole set; joining with
# "|" keeps it a single argument instead of a CMake list.
# Some of these ship as INTERFACE aliases over the real archive (pugixml), so
# each candidate is probed and only concrete libraries contribute a file.
set(KE_ASSIMP_LINK_TARGETS
    assimp::assimp
    polyclipping::polyclipping
    poly2tri::poly2tri
    pugixml::static
    pugixml::pugixml
    ZLIB::ZLIB
    zip::zip
    MINIZIP::minizip
    MINIZIP::minizipstatic)

set(KE_ASSIMP_LIBS "")
foreach(t IN LISTS KE_ASSIMP_LINK_TARGETS)
    if(NOT TARGET ${t})
        continue()
    endif()
    get_target_property(_t_type ${t} TYPE)
    if(_t_type STREQUAL "INTERFACE_LIBRARY")
        continue()
    endif()
    if(KE_ASSIMP_LIBS STREQUAL "")
        set(KE_ASSIMP_LIBS "$<TARGET_FILE:${t}>")
    else()
        set(KE_ASSIMP_LIBS "${KE_ASSIMP_LIBS}|$<TARGET_FILE:${t}>")
    endif()
endforeach()

# Assimp is C++, so the plugin needs the C++ runtime recorded as a dependency of
# its shared object (the managed layer dlopens it). Let CMake name the runtime
# for the active toolchain instead of hardcoding one; its development symlink
# lives in a compiler-private directory.
if(NOT MSVC)
    find_library(KE_CXX_RUNTIME
        NAMES stdc++ c++
        HINTS ${CMAKE_CXX_IMPLICIT_LINK_DIRECTORIES}
        REQUIRED)
    set(KE_CXX_RUNTIME_OPT "-Dcxx-runtime=${KE_CXX_RUNTIME}")
endif()

file(GLOB KE_ASSET_ASSIMP_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-asset-include=${CMAKE_SOURCE_DIR}/src/c/asset/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-scheduler-include=${CMAKE_SOURCE_DIR}/src/c/scheduler/include"
        "-Dassimp-include=${ASSIMP_INCLUDE_DIR}"
        "-Dassimp-libs=${KE_ASSIMP_LIBS}"
        "-Dstb-include=${STB_INCLUDE_DIR}"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        ${KE_CXX_RUNTIME_OPT}
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_ASSET_ASSIMP_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
    COMMENT "Building ke_asset_assimp (Zig)"
    VERBATIM
)

add_custom_target(ke_asset_assimp_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_asset_assimp_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_asset_assimp_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_asset_assimp.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_asset_assimp.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_asset_assimp SHARED IMPORTED GLOBAL)
add_dependencies(ke_asset_assimp ke_asset_assimp_zig)

set_target_properties(ke_asset_assimp PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/include"
    INTERFACE_LINK_LIBRARIES "ke_asset"
)

if(WIN32)
    set_target_properties(ke_asset_assimp PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_asset_assimp.lib"
    )
endif()

install(DIRECTORY include/ DESTINATION include)

# The conversion tests live in Zig (they assemble assimp structs the C API
# cannot build), so ctest drives them through `zig build test` rather than a
# gtest binary. Same options as the library itself.
add_test(NAME asset_assimp_zig_tests
    COMMAND "${ZIG_EXECUTABLE}" build test
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-asset-include=${CMAKE_SOURCE_DIR}/src/c/asset/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-scheduler-include=${CMAKE_SOURCE_DIR}/src/c/scheduler/include"
        "-Dassimp-include=${ASSIMP_INCLUDE_DIR}"
        "-Dassimp-libs=${KE_ASSIMP_LIBS}"
        "-Dstb-include=${STB_INCLUDE_DIR}"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        ${KE_CXX_RUNTIME_OPT}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)
