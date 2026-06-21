include(FetchContent)

# ── wgpu-native via WebGPU-distribution (same as the old render-v2 branch) ────
set(WEBGPU_BACKEND "WGPU" CACHE STRING "WebGPU backend (WGPU = wgpu-native)")
FetchContent_Declare(
    webgpu
    GIT_REPOSITORY https://github.com/eliemichel/WebGPU-distribution
    GIT_TAG        main
)
FetchContent_MakeAvailable(webgpu)

# webgpu-distribution exposes the `webgpu` target.
# $<TARGET_FILE_DIR:webgpu> resolves to the directory containing the wgpu_native shared library.

# ── Zig build step ─────────────────────────────────────────────────────────────

find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZIG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-out")
set(ZIG_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}ke_gpu_device_webgpu${CMAKE_SHARED_LIBRARY_SUFFIX}")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    COMMAND "${ZIG_EXECUTABLE}" build
        "--prefix" "${ZIG_OUT_DIR}"
        "-Dke-common-include=${CMAKE_SOURCE_DIR}/src/c/common/include"
        "-Dke-lib-dir=$<TARGET_LINKER_FILE_DIR:ke_common>"
        "-Dke-render-include=${CMAKE_SOURCE_DIR}/src/c/render/include"
        "-Dke-window-include=${CMAKE_SOURCE_DIR}/src/c/window/include"
        "-Dwgpu-include=$<TARGET_FILE_DIR:webgpu>/../include"
        "-Dwgpu-lib=$<TARGET_FILE_DIR:webgpu>"
        "$<IF:$<CONFIG:Debug>,--release=off,--release=fast>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/gpu_device_webgpu.zig"
        "${CMAKE_CURRENT_SOURCE_DIR}/build.zig"
        webgpu
        ke_common
    COMMENT "Building ke_gpu_device_webgpu (Zig)"
    VERBATIM
)

add_custom_target(ke_gpu_device_webgpu_zig ALL
    DEPENDS "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
)

add_custom_command(TARGET ke_gpu_device_webgpu_zig POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${ZIG_LIB_NAME}"
    VERBATIM
)

# ── Imported target ────────────────────────────────────────────────────────────

add_library(ke_gpu_device_webgpu SHARED IMPORTED GLOBAL)
add_dependencies(ke_gpu_device_webgpu ke_gpu_device_webgpu_zig)

set_target_properties(ke_gpu_device_webgpu PROPERTIES
    IMPORTED_LOCATION "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_SOURCE_DIR}/src/c/render/include"
)

if(WIN32)
    set_target_properties(ke_gpu_device_webgpu PROPERTIES
        IMPORTED_IMPLIB "${ZIG_OUT_DIR}/lib/ke_gpu_device_webgpu.lib"
    )
endif()

