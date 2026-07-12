# ke_compile_material_shaders — compiles every authored material across every
# directory in ${KE_MATERIALS_DIRS} for one consuming pass, taking the
# (material x pass) cartesian product the pass would otherwise have to
# hardcode.
#
# KE_MATERIALS_DIRS is a LIST, not a single directory: the engine ships its own
# defaults (src/shaders/materials/ — "standard", the built-in fallback) and a
# game appends its own tree alongside it (e.g. via
# `list(APPEND KE_MATERIALS_DIRS "${MY_GAME}/materials")` before the render
# passes are configured). Both coexist; a game never has to choose between "the
# engine defaults" and "my own materials".
#
# An authored material (some_dir/<name>.slang) is only a `struct X : IMaterial`
# — no entry point, no pass import, so it cannot be compiled alone. Each
# consuming pass ships a wrapper template that binds an IMaterial into its own
# entry points; generate_material_wrapper.py pairs the two. The result is
# compiled to <material>.<pass>.{vs,fs}.<ext>, which is the logical name the
# pass resolves at runtime via ke_render_core::load_shader once a material
# tells it which shader it wants.
#
# Adding a material to the project therefore means dropping a .slang in one of
# these directories — no pass, no CMakeLists, and no engine source changes.
#
# Usage (from a pass's CMakeLists.txt):
#   ke_compile_material_shaders(
#       PASS          gbuffer
#       TEMPLATE      "${CMAKE_CURRENT_SOURCE_DIR}/shaders/gbuffer_material.slang.in"
#       INCLUDES      "${KE_SHADER_LIB_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
#       EXTRA_DEPENDS ${GBUFFER_SHADER_DEPS}
#       OUT_FILES     out_var    # every produced file, for the ALL target
#   )
function(ke_compile_material_shaders)
    set(one_value_args PASS TEMPLATE OUT_FILES)
    set(multi_value_args INCLUDES EXTRA_DEPENDS)
    cmake_parse_arguments(ARG "" "${one_value_args}" "${multi_value_args}" ${ARGN})

    if(NOT KE_MATERIALS_DIRS)
        message(FATAL_ERROR "KE_MATERIALS_DIRS must be set (root CMakeLists.txt) before calling ke_compile_material_shaders")
    endif()

    # CONFIGURE_DEPENDS: adding or removing a material re-runs the glob, so a new
    # material is picked up by a plain build — no manual CMake re-configure.
    set(material_files)
    foreach(materials_dir ${KE_MATERIALS_DIRS})
        file(GLOB dir_materials CONFIGURE_DEPENDS "${materials_dir}/*.slang")
        list(APPEND material_files ${dir_materials})
    endforeach()

    set(produced)
    foreach(material ${material_files})
        get_filename_component(material_name "${material}" NAME_WE)
        set(wrapper "${CMAKE_CURRENT_BINARY_DIR}/gen/${material_name}.${ARG_PASS}.slang")

        add_custom_command(
            OUTPUT "${wrapper}"
            COMMAND "${Python3_EXECUTABLE}" "${KE_GENERATE_MATERIAL_WRAPPER_SCRIPT}"
                    --material "${material}"
                    --template "${ARG_TEMPLATE}"
                    --output   "${wrapper}"
            DEPENDS "${material}" "${ARG_TEMPLATE}" "${KE_GENERATE_MATERIAL_WRAPPER_SCRIPT}"
            COMMENT "Generating ${material_name} x ${ARG_PASS} material wrapper"
            VERBATIM
        )

        # The wrapper `import`s the material by module name, so every materials
        # dir must be on the compile include path alongside the pass's own —
        # Slang resolves the import by searching all of them.
        ke_compile_slang_shader(
            NAME "${material_name}.${ARG_PASS}" STAGE vertex ENTRY vs_main
            INPUT "${wrapper}"
            INCLUDES ${ARG_INCLUDES} ${KE_MATERIALS_DIRS}
            EXTRA_DEPENDS "${material}" ${ARG_EXTRA_DEPENDS}
            OUT_FILE vs_out
        )
        ke_compile_slang_shader(
            NAME "${material_name}.${ARG_PASS}" STAGE fragment ENTRY fs_main
            INPUT "${wrapper}"
            INCLUDES ${ARG_INCLUDES} ${KE_MATERIALS_DIRS}
            EXTRA_DEPENDS "${material}" ${ARG_EXTRA_DEPENDS}
            OUT_FILE fs_out
        )
        list(APPEND produced "${vs_out}" "${fs_out}")
    endforeach()

    if(ARG_OUT_FILES)
        set(${ARG_OUT_FILES} "${produced}" PARENT_SCOPE)
    endif()
endfunction()
