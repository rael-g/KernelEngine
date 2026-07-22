# c_demo_14 — built via Zig as the orchestrator. See
# examples/c/01_minimal_log/CMakeLists.txt for the full rationale.

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(KE_DEMO_INCLUDE_DIRS
    ${CMAKE_SOURCE_DIR}/src/c/spatial/include
    ${CMAKE_SOURCE_DIR}/src/c/window/include
    ${CMAKE_SOURCE_DIR}/src/c/ecs/include
    ${CMAKE_SOURCE_DIR}/src/c/scheduler/include
    ${CMAKE_SOURCE_DIR}/src/zig/common/include
    ${CMAKE_SOURCE_DIR}/src/c/render/include
    ${CMAKE_SOURCE_DIR}/src/zig/window/glfw/include
    ${CMAKE_SOURCE_DIR}/src/zig/render/webgpu/include
    ${CMAKE_SOURCE_DIR}/src/zig/render/core/include
    ${CMAKE_SOURCE_DIR}/src/zig/ecs/flecs/include
    ${CMAKE_SOURCE_DIR}/src/zig/scheduler/enki/include
    ${CMAKE_SOURCE_DIR}/src/c/runtime/include
)
list(JOIN KE_DEMO_INCLUDE_DIRS "|" KE_DEMO_INCLUDE_DIRS_JOINED)

set(KE_DEMO_LINK_TARGETS
    ke_common
    ke_window_glfw
    ke_gpu_device_webgpu
    ke_render_core
    ke_ecs_flecs
    ke_scheduler_enki
    ke_runtime
)
set(KE_DEMO_LIBS "")
foreach(t IN LISTS KE_DEMO_LINK_TARGETS)
    if(KE_DEMO_LIBS STREQUAL "")
        set(KE_DEMO_LIBS "$<TARGET_FILE:${t}>")
    else()
        set(KE_DEMO_LIBS "${KE_DEMO_LIBS}|$<TARGET_FILE:${t}>")
    endif()
endforeach()

set(KE_DEMO_ZIG_OUT "${CMAKE_CURRENT_BINARY_DIR}/zig-out/bin/demo")
set(KE_DEMO_OUTPUT "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/c_demo_14")

add_custom_command(
    OUTPUT "${KE_DEMO_ZIG_OUT}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${CMAKE_CURRENT_BINARY_DIR}/zig-out"
        "-Dinclude-dirs=${KE_DEMO_INCLUDE_DIRS_JOINED}"
        "-Dlibs=${KE_DEMO_LIBS}"
        "-Dlink-m=true"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/main.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        ${KE_DEMO_LINK_TARGETS}
    COMMENT "Building c_demo_14 (Zig-orchestrated)"
    VERBATIM
)

add_custom_target(c_demo_14_build ALL
    DEPENDS "${KE_DEMO_ZIG_OUT}"
)

add_custom_command(TARGET c_demo_14_build POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${KE_DEMO_ZIG_OUT}"
        "${KE_DEMO_OUTPUT}"
    VERBATIM
)

add_executable(c_demo_14 IMPORTED GLOBAL)
set_target_properties(c_demo_14 PROPERTIES
    IMPORTED_LOCATION "${KE_DEMO_OUTPUT}"
)
