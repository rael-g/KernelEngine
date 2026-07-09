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

# On platforms that link shared libraries through an import library, that file is
# a second product of the same zig invocation. It must be declared, or a consumer
# linking against IMPORTED_IMPLIB asks for a path the build graph cannot produce.
if(CMAKE_IMPORT_LIBRARY_SUFFIX)
    set(ZIG_IMPLIB_NAME "${CMAKE_IMPORT_LIBRARY_PREFIX}ke_gpu_device_webgpu${CMAKE_IMPORT_LIBRARY_SUFFIX}")
    set(ZIG_IMPLIB_OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_IMPLIB_NAME}")
endif()

# Zig resolves its own compilation unit from the @import graph, so CMake cannot
# know which files matter. Depend on all of them: a source omitted here rebuilds
# nothing and ships a stale binary, which fails silently at runtime.
# CONFIGURE_DEPENDS re-runs the glob when a file is added or removed.
file(GLOB KE_GPU_DEVICE_WEBGPU_ZIG_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.zig")

add_custom_command(
    OUTPUT "${ZIG_OUT_DIR}/lib/${ZIG_LIB_NAME}" ${ZIG_IMPLIB_OUTPUT}
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
        ${KE_GPU_DEVICE_WEBGPU_ZIG_SOURCES}
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
    # wgpu-native is linked dynamically, so every consumer of this module needs
    # its shared library beside them at run time. It lives inside the fetched
    # dependency's tree, which is on no loader search path.
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "$<TARGET_FILE:webgpu>"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/$<TARGET_FILE_NAME:webgpu>"
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

if(ZIG_IMPLIB_OUTPUT)
    set_target_properties(ke_gpu_device_webgpu PROPERTIES
        IMPORTED_IMPLIB "${ZIG_IMPLIB_OUTPUT}"
    )
endif()

