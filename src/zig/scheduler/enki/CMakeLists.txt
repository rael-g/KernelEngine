# ke_scheduler_enki — the enkiTS-backed task scheduler, built in Zig.
# Mirrors src/zig/window/glfw's zig-build-as-imported-target pattern: the plugin
# talks to enkiTS through its C API, so nothing here needs a C++ compiler even
# though enkiTS itself is C++.

find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(enkiTS CONFIG REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_scheduler_enki${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(KE_ZIG_ERROR "${CMAKE_SOURCE_DIR}/src/zig/common/kerror.zig")

# Derive the headers and library location from the imported target rather than
# hardcoding a vcpkg triplet path.
get_target_property(ENKI_INCLUDE_DIRS enkiTS::enkiTS INTERFACE_INCLUDE_DIRECTORIES)
list(GET ENKI_INCLUDE_DIRS 0 ENKI_INCLUDE_DIR)

# enkiTS is C++, so the plugin needs the C++ runtime recorded as a dependency of
# its shared object (the managed layer dlopens it). Let CMake name the runtime
# for the active toolchain instead of hardcoding one.
if(NOT MSVC)
    # The runtime's development symlink lives in a compiler-private directory,
    # so search the ones the CXX toolchain itself reports.
    find_library(KE_CXX_RUNTIME
        NAMES stdc++ c++
        HINTS ${CMAKE_CXX_IMPLICIT_LINK_DIRECTORIES}
        REQUIRED)
    set(KE_CXX_RUNTIME_OPT "-Dcxx-runtime=${KE_CXX_RUNTIME}")
endif()

file(GLOB KE_SCHEDULER_ENKI_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/zig/common/include"
        "-Dke-scheduler-include=${CMAKE_SOURCE_DIR}/src/c/scheduler/include"
        "-Denki-include=${ENKI_INCLUDE_DIR}"
        "-Denki-lib=$<TARGET_FILE_DIR:enkiTS::enkiTS>"
        "-Dkerror-src=${KE_ZIG_ERROR}"
        ${KE_CXX_RUNTIME_OPT}
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_SCHEDULER_ENKI_ZIG_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${KE_ZIG_ERROR}"
    COMMENT "Building ke_scheduler_enki (Zig)"
    VERBATIM
)

add_custom_target(ke_scheduler_enki_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_scheduler_enki_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# Only Windows produces a separate import library to link against; ELF links
# directly against the shared object.
if(WIN32)
    add_custom_command(TARGET ke_scheduler_enki_zig POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${ZIG_OUT_DIR}/lib/ke_scheduler_enki.lib"
            "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ke_scheduler_enki.lib"
        VERBATIM
    )
endif()

# ── Imported target ──────────────────────────────────────────────────────────

add_library(ke_scheduler_enki SHARED IMPORTED GLOBAL)
add_dependencies(ke_scheduler_enki ke_scheduler_enki_zig)

set_target_properties(ke_scheduler_enki PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/include"
    INTERFACE_LINK_LIBRARIES "ke_scheduler"
)

if(WIN32)
    set_target_properties(ke_scheduler_enki PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_scheduler_enki.lib"
    )
endif()

install(DIRECTORY include/ DESTINATION include)
