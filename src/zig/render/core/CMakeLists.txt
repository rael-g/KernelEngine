find_program(ZIG_EXECUTABLE zig REQUIRED)
find_package(Python3 COMPONENTS Interpreter REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_render_core${CMAKE_SHARED_LIBRARY_SUFFIX}")

# Compile the forward pass shader (Slang -> WGSL) for @embedFile in the Zig lib.
set(COMPILE_SLANG "${CMAKE_SOURCE_DIR}/scripts/compile_slang.py")
set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${SHADER_GEN_DIR}")
# One WGSL module per stage: a uniform shared across stages would be declared
# twice (invalid WGSL) if both entry points were emitted into one module.
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/forward.vs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry vs_main --stage vertex
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/forward.slang"
            --output "${SHADER_GEN_DIR}/forward.vs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/forward.slang" "${COMPILE_SLANG}"
    VERBATIM
)
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/forward.fs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry fs_main --stage fragment
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/forward.slang"
            --output "${SHADER_GEN_DIR}/forward.fs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/forward.slang" "${COMPILE_SLANG}"
    VERBATIM
)
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/skybox.vs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry vs_main --stage vertex
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/skybox.slang"
            --output "${SHADER_GEN_DIR}/skybox.vs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/skybox.slang" "${COMPILE_SLANG}"
    VERBATIM
)
add_custom_command(
    OUTPUT "${SHADER_GEN_DIR}/skybox.fs.wgsl"
    COMMAND "${Python3_EXECUTABLE}" "${COMPILE_SLANG}"
            --raw --target wgsl --entry fs_main --stage fragment
            --input  "${CMAKE_CURRENT_SOURCE_DIR}/shaders/skybox.slang"
            --output "${SHADER_GEN_DIR}/skybox.fs.wgsl"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders/skybox.slang" "${COMPILE_SLANG}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}" "${ZIG_OUT_DIR}/lib/ke_render_core.lib"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-allocator-include=${CMAKE_SOURCE_DIR}/src/c/allocator/include"
        "-Dke-ecs-include=${CMAKE_SOURCE_DIR}/src/c/ecs/include"
        "-Dke-runtime-include=${CMAKE_SOURCE_DIR}/src/c/runtime/include"
        "-Dke-spatial-include=${CMAKE_SOURCE_DIR}/src/c/spatial/include"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-self-include=${CMAKE_CURRENT_SOURCE_DIR}/include"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "-Dforward-vs-wgsl=${SHADER_GEN_DIR}/forward.vs.wgsl"
        "-Dforward-fs-wgsl=${SHADER_GEN_DIR}/forward.fs.wgsl"
        "-Dskybox-vs-wgsl=${SHADER_GEN_DIR}/skybox.vs.wgsl"
        "-Dskybox-fs-wgsl=${SHADER_GEN_DIR}/skybox.fs.wgsl"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/render_core.zig"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/render_module.zig"
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        "${SHADER_GEN_DIR}/forward.vs.wgsl"
        "${SHADER_GEN_DIR}/forward.fs.wgsl"
        "${SHADER_GEN_DIR}/skybox.vs.wgsl"
        "${SHADER_GEN_DIR}/skybox.fs.wgsl"
        ke_common
        ke_runtime
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
