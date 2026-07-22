# test_integration_cpp — built via Zig as the orchestrator instead of a
# hand-written add_executable/target_link_libraries pair. The test sources
# stay C++/GTest untouched; only the build DEFINITION moved to build.zig,
# which shells out to the SYSTEM C++ compiler (not Zig's own C++ frontend —
# see build.zig for why: an ABI mismatch against vcpkg's GTest archives).
# Mirrors the zig-build-as-imported-target pattern every migrated plugin uses
# (e.g. src/zig/physics/box2d/CMakeLists.txt), applied to an executable.

find_package(GTest CONFIG REQUIRED)
find_package(assimp CONFIG REQUIRED)

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(KE_TEST_INTEGRATION_SOURCES
    test_world.cpp
    test_factories.cpp
    test_window_glfw.cpp
    test_asset_loader.cpp
    test_stb_image_loader.cpp
    test_enki_scheduler.cpp
    test_miniaudio_audio.cpp
    test_box2d_physics.cpp
    test_stb_font.cpp
    test_runtime.cpp
    test_ecs_parallel_reads.cpp
)
list(TRANSFORM KE_TEST_INTEGRATION_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
list(JOIN KE_TEST_INTEGRATION_SOURCES "|" KE_TEST_INTEGRATION_SOURCES_JOINED)

set(KE_TEST_INTEGRATION_INCLUDE_DIRS
    ${CMAKE_SOURCE_DIR}/src/c/window/include
    ${CMAKE_SOURCE_DIR}/src/c/allocator/include
    ${CMAKE_SOURCE_DIR}/src/c/render/include
    ${CMAKE_SOURCE_DIR}/src/c/spatial/include
    ${CMAKE_SOURCE_DIR}/src/c/scheduler/include
    ${CMAKE_SOURCE_DIR}/src/c/physics/include
    ${CMAKE_SOURCE_DIR}/src/c/logger/include
    ${CMAKE_SOURCE_DIR}/src/c/input/include
    ${CMAKE_SOURCE_DIR}/src/c/resource_cache/include
    ${CMAKE_SOURCE_DIR}/src/c/ecs/include
    ${CMAKE_SOURCE_DIR}/src/zig/scheduler/enki/include
    ${CMAKE_SOURCE_DIR}/src/zig/audio/miniaudio/include
    ${CMAKE_SOURCE_DIR}/src/zig/physics/box2d/include
    ${CMAKE_SOURCE_DIR}/src/zig/text/stb_truetype/include
    ${CMAKE_SOURCE_DIR}/src/zig/window/glfw/include
    ${CMAKE_SOURCE_DIR}/src/zig/asset/assimp/include
    ${CMAKE_SOURCE_DIR}/src/c/asset/include
    ${CMAKE_SOURCE_DIR}/src/zig/common/include
    ${CMAKE_SOURCE_DIR}/src/c/text/include
    ${CMAKE_SOURCE_DIR}/src/zig/asset/stb_image/include
    ${CMAKE_SOURCE_DIR}/src/c/audio/include
    ${CMAKE_SOURCE_DIR}/src/c/runtime/include
    ${CMAKE_SOURCE_DIR}/src/zig/ecs/flecs/include
    ${CMAKE_SOURCE_DIR}/src/zig/framework/include
)
get_target_property(KE_VCPKG_INCLUDE_DIR GTest::gtest INTERFACE_INCLUDE_DIRECTORIES)
list(APPEND KE_TEST_INTEGRATION_INCLUDE_DIRS ${KE_VCPKG_INCLUDE_DIR})
list(JOIN KE_TEST_INTEGRATION_INCLUDE_DIRS "|" KE_TEST_INTEGRATION_INCLUDE_DIRS_JOINED)

# Libraries in the same order CMake's own dependency resolution linked them.
set(KE_TEST_INTEGRATION_LINK_TARGETS
    ke_window_glfw
    ke_asset_assimp
    ke_asset_stb_image
    ke_scheduler_enki
    ke_audio_miniaudio
    ke_physics_2d_box2d
    ke_text_stb_truetype
    ke_allocator_malloc
    ke_logger_simple
    ke_input_default
    ke_resource_cache_default
    ke_runtime
    ke_ecs_flecs
    ke_framework
    GTest::gtest_main
    GTest::gmock
    ke_common
    GTest::gtest
)
set(KE_TEST_INTEGRATION_LIBS "")
set(KE_TEST_INTEGRATION_RPATHS "")
foreach(t IN LISTS KE_TEST_INTEGRATION_LINK_TARGETS)
    if(KE_TEST_INTEGRATION_LIBS STREQUAL "")
        set(KE_TEST_INTEGRATION_LIBS "$<TARGET_FILE:${t}>")
    else()
        set(KE_TEST_INTEGRATION_LIBS "${KE_TEST_INTEGRATION_LIBS}|$<TARGET_FILE:${t}>")
    endif()
    get_target_property(_t_type ${t} TYPE)
    if(NOT _t_type STREQUAL "STATIC_LIBRARY")
        if(KE_TEST_INTEGRATION_RPATHS STREQUAL "")
            set(KE_TEST_INTEGRATION_RPATHS "$<TARGET_FILE_DIR:${t}>")
        else()
            set(KE_TEST_INTEGRATION_RPATHS "${KE_TEST_INTEGRATION_RPATHS}|$<TARGET_FILE_DIR:${t}>")
        endif()
    endif()
endforeach()

# Two distinct paths, like every other zig-build-as-imported-target plugin:
# zig build writes to its own zig-out location; a separate POST_BUILD step
# copies it to the final CMAKE_RUNTIME_OUTPUT_DIRECTORY path. Writing directly
# to the final path and pointing IMPORTED_LOCATION at that same file made
# CMake silently drop the add_custom_command's rule entirely (verified: the
# rule never appeared in the generated build.ninja, no error given) — CMake
# seems to treat a path that is also an IMPORTED_LOCATION as externally
# provided, and skips generating a rule to produce it.
set(KE_TEST_INTEGRATION_ZIG_OUT "${CMAKE_CURRENT_BINARY_DIR}/zig-out/test_integration_cpp")
set(KE_TEST_INTEGRATION_OUTPUT "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/test_integration_cpp")

add_custom_command(
    OUTPUT "${KE_TEST_INTEGRATION_ZIG_OUT}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "-Dsources=${KE_TEST_INTEGRATION_SOURCES_JOINED}"
        "-Dinclude-dirs=${KE_TEST_INTEGRATION_INCLUDE_DIRS_JOINED}"
        "-Dlibs=${KE_TEST_INTEGRATION_LIBS}"
        "-Drpaths=${KE_TEST_INTEGRATION_RPATHS}"
        "-Ddefines=KE_KERNEL_STATIC"
        "-Doutput=${KE_TEST_INTEGRATION_ZIG_OUT}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_TEST_INTEGRATION_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        ${KE_TEST_INTEGRATION_LINK_TARGETS}
    COMMENT "Building test_integration_cpp (Zig-orchestrated, system C++ compiler)"
    VERBATIM
)

add_custom_target(test_integration_cpp_build ALL
    DEPENDS "${KE_TEST_INTEGRATION_ZIG_OUT}"
)

add_custom_command(TARGET test_integration_cpp_build POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${KE_TEST_INTEGRATION_ZIG_OUT}"
        "${KE_TEST_INTEGRATION_OUTPUT}"
    VERBATIM
)

# No add_dependencies(test_integration_cpp test_integration_cpp_build) here:
# CMake 3.28 reports a spurious self-referencing dependency cycle on the
# custom target when an IMPORTED EXECUTABLE (not IMPORTED library — those are
# fine, see every other migrated plugin) depends on it via add_dependencies.
# Not needed anyway — test_integration_cpp_build is already part of ALL, so
# `cmake --build` produces the binary before ctest ever runs; this imported
# target exists only so $<TARGET_FILE:test_integration_cpp> resolves for
# gtest_discover_tests.
add_executable(test_integration_cpp IMPORTED GLOBAL)
set_target_properties(test_integration_cpp PROPERTIES
    IMPORTED_LOCATION "${KE_TEST_INTEGRATION_OUTPUT}"
)

# PRE_TEST: discovery runs at ctest time rather than via a POST_BUILD hook —
# IMPORTED targets (this one included, since the real build step is the
# add_custom_command above) can't carry a POST_BUILD command of their own.
include(GoogleTest)
gtest_discover_tests(test_integration_cpp
    DISCOVERY_MODE PRE_TEST
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    PROPERTIES LABELS "integration")
