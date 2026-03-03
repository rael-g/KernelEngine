add_library(ke_shader_compiler_bgfx
    bgfx_shader_compiler.cc
)

get_target_property(target_type ke_shader_compiler_bgfx TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_shader_compiler_bgfx PUBLIC KE_SHADER_COMPILER_STATIC)
else()
    target_compile_definitions(ke_shader_compiler_bgfx PRIVATE KE_SHADER_COMPILER_EXPORT)
endif()

target_include_directories(ke_shader_compiler_bgfx PUBLIC
    ${CMAKE_SOURCE_DIR}/src/c/core/include
)

target_link_libraries(ke_shader_compiler_bgfx PUBLIC 
    ke_core
)
