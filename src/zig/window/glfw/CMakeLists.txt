# ke_window_glfw — the GLFW-backed window plugin, built in Zig.
# Mirrors src/zig/logger/simple's zig-build-as-imported-target pattern.
#
# The backend-agnostic core and the GLFW device stay separate source files
# behind a Zig device vtable, so a second backend is a new file filling that
# struct rather than a rewrite — the split the C++ version expressed with a
# virtual interface.

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(glfw3 CONFIG REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_window_glfw${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")

# vcpkg installs GLFW's headers and library under the same prefix; derive both
# from the imported target rather than hardcoding a triplet path.
get_target_property(GLFW_INCLUDE_DIRS glfw INTERFACE_INCLUDE_DIRECTORIES)
list(GET GLFW_INCLUDE_DIRS 0 GLFW_INCLUDE_DIR)

file(GLOB KE_WINDOW_GLFW_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-window-include=${CMAKE_SOURCE_DIR}/src/c/window/include"
        "-Dke-input-include=${CMAKE_SOURCE_DIR}/src/c/input/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dglfw-include=${GLFW_INCLUDE_DIR}"
        "-Dglfw-lib=$<TARGET_FILE_DIR:glfw>"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_WINDOW_GLFW_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
    COMMENT "Building ke_window_glfw (Zig)"
    VERBATIM
)

add_custom_target(ke_window_glfw_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_window_glfw_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_window_glfw_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_window_glfw.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_window_glfw.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_window_glfw SHARED IMPORTED GLOBAL)
add_dependencies(ke_window_glfw ke_window_glfw_zig)

set_target_properties(ke_window_glfw PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

if(WIN32)
    set_target_properties(ke_window_glfw PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_window_glfw.lib"
    )
endif()

install(DIRECTORY include/ DESTINATION include)

# The core's unit tests live in Zig (the device seam they substitute is a Zig
# vtable), so ctest drives them through `zig build test` rather than a gtest
# binary. Same build options as the library itself.
add_test(NAME window_glfw_zig_tests
    COMMAND "${ZIG_EXECUTABLE}" build test
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-window-include=${CMAKE_SOURCE_DIR}/src/c/window/include"
        "-Dke-input-include=${CMAKE_SOURCE_DIR}/src/c/input/include"
        "-Dke-logger-include=${CMAKE_SOURCE_DIR}/src/c/logger/include"
        "-Dglfw-include=${GLFW_INCLUDE_DIR}"
        "-Dglfw-lib=$<TARGET_FILE_DIR:glfw>"
        "-Dkerror-src=${KE_ZIG_ERROR}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)
