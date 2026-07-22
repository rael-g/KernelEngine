# test_ke_kernel — built via Zig as the orchestrator instead of a hand-written
# add_executable/target_link_libraries pair. See tests/integration/cpp/CMakeLists.txt
# for the full rationale (same pattern, applied here).

find_package(GTest CONFIG REQUIRED)
find_program(ZIG_EXECUTABLE zig REQUIRED)

set(KE_TEST_KERNEL_SOURCES
    #   test_allocator.cpp     -- deleted: ke_allocator (allocator.h/ke_allocator_malloc) removed, no consumers left
    #   test_hash_map.cpp      -- deleted: hash_map.h removed (domain ejection)
    #   test_ecs.cpp           -- deleted: ke_ecs_registry_create removed (legacy sparse-set ECS replaced by ke_ecs_flecs)
    test_input.cpp
    test_logger.cpp
    #   test_hash.cpp          -- deleted: hash.h removed (domain ejection)
    #   test_array.cpp         -- deleted: array.h removed (domain ejection)
    test_asset_resolver.cpp  # C-phase 1: re-enabled with new ke_framework plugin
    test_resource_cache.cpp  # C-phase 2: re-enabled as kernel built-in
    test_scene_tree.cpp      # C-phase 3: re-enabled with ecs-backed scene_tree
    test_input_actions.cpp   # C-phase 5: re-enabled with pure-C input_actions impl
    test_scene_loader.cpp    # C-phase 6: re-enabled with pure-C scene_loader + apply registry
    #   test_mesh_shape.cpp    -- legacy header API gone; replaced by asset_resolver
    #   test_material_file.cpp -- legacy header API gone; replaced by asset_resolver
)
list(TRANSFORM KE_TEST_KERNEL_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
list(JOIN KE_TEST_KERNEL_SOURCES "|" KE_TEST_KERNEL_SOURCES_JOINED)

set(KE_TEST_KERNEL_INCLUDE_DIRS
    ${CMAKE_SOURCE_DIR}/src/c/logger/include
    ${CMAKE_SOURCE_DIR}/src/c/ecs/include
    ${CMAKE_SOURCE_DIR}/src/c/spatial/include
    ${CMAKE_SOURCE_DIR}/src/c/scheduler/include
    ${CMAKE_SOURCE_DIR}/src/c/framework/include
    ${CMAKE_SOURCE_DIR}/src/c/render/include
    ${CMAKE_SOURCE_DIR}/src/c/input/include
    ${CMAKE_SOURCE_DIR}/src/c/asset/include
    ${CMAKE_SOURCE_DIR}/src/c/resource_cache/include
    ${CMAKE_SOURCE_DIR}/src/c/text/include
    ${CMAKE_SOURCE_DIR}/src/zig/common/include
    ${CMAKE_SOURCE_DIR}/src/c/runtime/include
    ${CMAKE_SOURCE_DIR}/src/zig/framework/include
    ${CMAKE_SOURCE_DIR}/src/zig/ecs/flecs/include
    ${CMAKE_SOURCE_DIR}/src/zig/scheduler/enki/include
)
get_target_property(KE_VCPKG_INCLUDE_DIR GTest::gtest INTERFACE_INCLUDE_DIRECTORIES)
list(APPEND KE_TEST_KERNEL_INCLUDE_DIRS ${KE_VCPKG_INCLUDE_DIR})
list(JOIN KE_TEST_KERNEL_INCLUDE_DIRS "|" KE_TEST_KERNEL_INCLUDE_DIRS_JOINED)

# Libraries in the same order CMake's own dependency resolution linked them.
set(KE_TEST_KERNEL_LINK_TARGETS
    ke_logger_simple
    ke_input_default
    ke_resource_cache_default
    ke_framework
    ke_runtime
    ke_ecs_flecs
    ke_scheduler_enki
    GTest::gtest_main
    ke_common
    GTest::gtest
)
set(KE_TEST_KERNEL_LIBS "")
set(KE_TEST_KERNEL_RPATHS "")
foreach(t IN LISTS KE_TEST_KERNEL_LINK_TARGETS)
    if(KE_TEST_KERNEL_LIBS STREQUAL "")
        set(KE_TEST_KERNEL_LIBS "$<TARGET_FILE:${t}>")
    else()
        set(KE_TEST_KERNEL_LIBS "${KE_TEST_KERNEL_LIBS}|$<TARGET_FILE:${t}>")
    endif()
    get_target_property(_t_type ${t} TYPE)
    if(NOT _t_type STREQUAL "STATIC_LIBRARY")
        if(KE_TEST_KERNEL_RPATHS STREQUAL "")
            set(KE_TEST_KERNEL_RPATHS "$<TARGET_FILE_DIR:${t}>")
        else()
            set(KE_TEST_KERNEL_RPATHS "${KE_TEST_KERNEL_RPATHS}|$<TARGET_FILE_DIR:${t}>")
        endif()
    endif()
endforeach()

# Two distinct paths, like every other zig-build-as-imported-target plugin —
# see tests/integration/cpp/CMakeLists.txt for why this can't collapse into one.
set(KE_TEST_KERNEL_ZIG_OUT "${CMAKE_CURRENT_BINARY_DIR}/zig-out/test_ke_kernel")
set(KE_TEST_KERNEL_OUTPUT "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/test_ke_kernel")

add_custom_command(
    OUTPUT "${KE_TEST_KERNEL_ZIG_OUT}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "-Dsources=${KE_TEST_KERNEL_SOURCES_JOINED}"
        "-Dinclude-dirs=${KE_TEST_KERNEL_INCLUDE_DIRS_JOINED}"
        "-Dlibs=${KE_TEST_KERNEL_LIBS}"
        "-Drpaths=${KE_TEST_KERNEL_RPATHS}"
        "-Doutput=${KE_TEST_KERNEL_ZIG_OUT}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        ${KE_TEST_KERNEL_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        ${KE_TEST_KERNEL_LINK_TARGETS}
    COMMENT "Building test_ke_kernel (Zig-orchestrated, system C++ compiler)"
    VERBATIM
)

add_custom_target(test_ke_kernel_build ALL
    DEPENDS "${KE_TEST_KERNEL_ZIG_OUT}"
)

add_custom_command(TARGET test_ke_kernel_build POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${KE_TEST_KERNEL_ZIG_OUT}"
        "${KE_TEST_KERNEL_OUTPUT}"
    VERBATIM
)

# No add_dependencies(test_ke_kernel test_ke_kernel_build): CMake 3.28 reports
# a spurious self-referencing cycle for that combination on an IMPORTED
# EXECUTABLE (see tests/integration/cpp/CMakeLists.txt). Not needed — ALL
# already builds it before ctest runs.
add_executable(test_ke_kernel IMPORTED GLOBAL)
set_target_properties(test_ke_kernel PROPERTIES
    IMPORTED_LOCATION "${KE_TEST_KERNEL_OUTPUT}"
)

include(GoogleTest)
gtest_discover_tests(test_ke_kernel
    DISCOVERY_MODE PRE_TEST
)
