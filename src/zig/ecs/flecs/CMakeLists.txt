# ke_ecs_flecs — the flecs-backed ECS plugin, built in Zig.
# Mirrors src/zig/physics/box2d's zig-build-as-imported-target pattern. flecs
# ships a C API, so nothing here needs a C++ compiler.

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(flecs CONFIG REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_ecs_flecs${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")

# Derive headers and library location from the imported target rather than
# hardcoding a vcpkg triplet path. flecs::flecs is an alias for the real
# archive target, flecs::flecs_static.
get_target_property(FLECS_INCLUDE_DIRS flecs::flecs_static INTERFACE_INCLUDE_DIRECTORIES)
list(GET FLECS_INCLUDE_DIRS 0 FLECS_INCLUDE_DIR)

file(GLOB KE_ECS_FLECS_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dflecs-include=${FLECS_INCLUDE_DIR}"
        "-Dflecs-lib=$<TARGET_FILE:flecs::flecs_static>"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_ECS_FLECS_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
    COMMENT "Building ke_ecs_flecs (Zig)"
    VERBATIM
)

add_custom_target(ke_ecs_flecs_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_ecs_flecs_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_ecs_flecs_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_ecs_flecs.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_ecs_flecs.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_ecs_flecs SHARED IMPORTED GLOBAL)
add_dependencies(ke_ecs_flecs ke_ecs_flecs_zig)

set_target_properties(ke_ecs_flecs PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/include"
    INTERFACE_LINK_LIBRARIES "ke_ecs"
)

if(WIN32)
    set_target_properties(ke_ecs_flecs PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_ecs_flecs.lib"
    )
endif()

install(DIRECTORY include/ DESTINATION include)

# The abort-handler message-capture test lives in Zig (it exercises a private
# function directly), so ctest drives it through `zig build test` rather than
# a gtest binary. Same options as the library itself.
add_test(NAME ecs_flecs_zig_tests
    COMMAND "${ZIG_EXECUTABLE}" build test
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dflecs-include=${FLECS_INCLUDE_DIR}"
        "-Dflecs-lib=$<TARGET_FILE:flecs::flecs_static>"
        "-Dkerror-src=${KE_ZIG_ERROR}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)
