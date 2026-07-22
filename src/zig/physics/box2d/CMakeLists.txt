# ke_physics_2d_box2d — the Box2D-backed 2D physics plugin, built in Zig.
# Mirrors src/zig/window/glfw's zig-build-as-imported-target pattern. Box2D v3
# ships a C API, so nothing here needs a C++ compiler.

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(box2d CONFIG REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_physics_2d_box2d${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")

# Derive headers and library location from the imported target rather than
# hardcoding a vcpkg triplet path.
get_target_property(BOX2D_INCLUDE_DIRS box2d::box2d INTERFACE_INCLUDE_DIRECTORIES)
list(GET BOX2D_INCLUDE_DIRS 0 BOX2D_INCLUDE_DIR)

file(GLOB KE_PHYSICS_BOX2D_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-physics-include=${CMAKE_SOURCE_DIR}/src/c/physics/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dbox2d-include=${BOX2D_INCLUDE_DIR}"
        "-Dbox2d-lib=$<TARGET_FILE:box2d::box2d>"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_PHYSICS_BOX2D_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
    COMMENT "Building ke_physics_2d_box2d (Zig)"
    VERBATIM
)

add_custom_target(ke_physics_2d_box2d_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_physics_2d_box2d_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_physics_2d_box2d_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_physics_2d_box2d.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_physics_2d_box2d.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_physics_2d_box2d SHARED IMPORTED GLOBAL)
add_dependencies(ke_physics_2d_box2d ke_physics_2d_box2d_zig)

set_target_properties(ke_physics_2d_box2d PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

if(WIN32)
    set_target_properties(ke_physics_2d_box2d PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_physics_2d_box2d.lib"
    )
endif()

install(DIRECTORY include/ DESTINATION include)
