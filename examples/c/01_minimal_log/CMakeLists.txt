# c_demo_01 — built via Zig as the orchestrator instead of a hand-written
# add_executable/target_link_libraries pair. Plain C, so build.zig compiles it
# with Zig's own C frontend directly (no ABI concerns, unlike the GTest suites).

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(KE_DEMO_INCLUDE_DIRS
    ${CMAKE_SOURCE_DIR}/src/c/logger/include
    ${CMAKE_SOURCE_DIR}/src/zig/common/include
)
list(JOIN KE_DEMO_INCLUDE_DIRS "|" KE_DEMO_INCLUDE_DIRS_JOINED)

set(KE_DEMO_LINK_TARGETS
    ke_logger_simple
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
set(KE_DEMO_OUTPUT "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/c_demo_01")

add_custom_command(
    OUTPUT "${KE_DEMO_ZIG_OUT}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${CMAKE_CURRENT_BINARY_DIR}/zig-out"
        "-Dinclude-dirs=${KE_DEMO_INCLUDE_DIRS_JOINED}"
        "-Dlibs=${KE_DEMO_LIBS}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/main.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        ${KE_DEMO_LINK_TARGETS}
    COMMENT "Building c_demo_01 (Zig-orchestrated)"
    VERBATIM
)

add_custom_target(c_demo_01_build ALL
    DEPENDS "${KE_DEMO_ZIG_OUT}"
)

add_custom_command(TARGET c_demo_01_build POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${KE_DEMO_ZIG_OUT}"
        "${KE_DEMO_OUTPUT}"
    VERBATIM
)

add_executable(c_demo_01 IMPORTED GLOBAL)
set_target_properties(c_demo_01 PROPERTIES
    IMPORTED_LOCATION "${KE_DEMO_OUTPUT}"
)
