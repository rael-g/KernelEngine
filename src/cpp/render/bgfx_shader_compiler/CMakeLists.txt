add_library(ke_shader_compiler_bgfx
    src/bgfx_shader_compiler.cpp
)

get_target_property(target_type ke_shader_compiler_bgfx TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_shader_compiler_bgfx PUBLIC KE_SHADER_COMPILER_BGFX_STATIC)
else()
    target_compile_definitions(ke_shader_compiler_bgfx PRIVATE KE_SHADER_COMPILER_BGFX_EXPORT)
endif()

target_include_directories(ke_shader_compiler_bgfx PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_link_libraries(ke_shader_compiler_bgfx PUBLIC 
    ke_render
    ke_logger
    ke_common
)

install(TARGETS ke_shader_compiler_bgfx
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

# Install the kernel_engine folder into include/
install(DIRECTORY include/kernel_engine DESTINATION include)
