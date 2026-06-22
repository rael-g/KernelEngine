find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_render_core${CMAKE_SHARED_LIBRARY_SUFFIX}")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}" "${ZIG_OUT_DIR}/lib/ke_render_core.lib"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-allocator-include=${CMAKE_SOURCE_DIR}/src/c/allocator/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dke-runtime-include=${CMAKE_SOURCE_DIR}/src/c/runtime/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/render_core.zig"
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        ke_common
    VERBATIM
)

add_custom_target(ke_render_core_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_render_core_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

add_library(ke_render_core SHARED IMPORTED GLOBAL)
add_dependencies(ke_render_core ke_render_core_zig)

set_target_properties(ke_render_core PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/render/include"
)

if(WIN32)
    set_target_properties(ke_render_core PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_render_core.lib"
    )
endif()
