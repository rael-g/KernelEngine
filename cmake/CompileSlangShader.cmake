# ke_compile_slang_shader — compiles one Slang entry point to the engine's
# active shader target (KE_SHADER_TARGET, set once at the root CMakeLists.txt)
# and installs the result under the shared runtime shaders directory
# (${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/shaders/<name>.<stage-suffix>.<ext>) so any
# render-core-owned pass can find it by logical name at runtime via
# ke_render_core::load_shader — a pass never invokes compile_slang.py itself
# and never names a shader format.
#
# Usage:
#   ke_compile_slang_shader(
#       NAME          tonemap        # logical name a pass will load_shader() by
#       STAGE         vertex         # vertex | fragment | compute
#       ENTRY         vs_main
#       INPUT         "${CMAKE_CURRENT_SOURCE_DIR}/shaders/tonemap.slang"
#       INCLUDES      "${KE_SHADER_LIB_DIR}"
#       EXTRA_DEPENDS "${KE_SHADER_LIB_DIR}/ke.slang"
#       OUT_FILE      out_var        # receives the produced file's path
#   )
function(ke_compile_slang_shader)
    set(one_value_args NAME STAGE ENTRY INPUT OUT_FILE)
    set(multi_value_args INCLUDES EXTRA_DEPENDS)
    cmake_parse_arguments(ARG "" "${one_value_args}" "${multi_value_args}" ${ARGN})

    if(NOT KE_SHADER_TARGET)
        message(FATAL_ERROR "KE_SHADER_TARGET must be set (root CMakeLists.txt) before calling ke_compile_slang_shader")
    endif()

    if(ARG_STAGE STREQUAL "vertex")
        set(stage_suffix "vs")
    elseif(ARG_STAGE STREQUAL "fragment")
        set(stage_suffix "fs")
    elseif(ARG_STAGE STREQUAL "compute")
        set(stage_suffix "cs")
    else()
        message(FATAL_ERROR "ke_compile_slang_shader: unknown STAGE '${ARG_STAGE}' (expected vertex|fragment|compute)")
    endif()

    set(shaders_out_dir "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/shaders")
    file(MAKE_DIRECTORY "${shaders_out_dir}")
    set(out_file "${shaders_out_dir}/${ARG_NAME}.${stage_suffix}.${KE_SHADER_TARGET}")

    set(include_args)
    foreach(dir ${ARG_INCLUDES})
        list(APPEND include_args --include "${dir}")
    endforeach()

    add_custom_command(
        OUTPUT "${out_file}"
        COMMAND "${Python3_EXECUTABLE}" "${KE_COMPILE_SLANG_SCRIPT}"
                --raw --target "${KE_SHADER_TARGET}" --entry "${ARG_ENTRY}" --stage "${ARG_STAGE}"
                ${include_args}
                --input  "${ARG_INPUT}"
                --output "${out_file}"
        DEPENDS "${ARG_INPUT}" "${KE_COMPILE_SLANG_SCRIPT}" ${ARG_EXTRA_DEPENDS}
        VERBATIM
    )

    if(ARG_OUT_FILE)
        set(${ARG_OUT_FILE} "${out_file}" PARENT_SCOPE)
    endif()
endfunction()
