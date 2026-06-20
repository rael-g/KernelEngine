add_executable(c_demo_04
    main.c
)

target_link_libraries(c_demo_04 PRIVATE
    ke_allocator_malloc
    ke_logger_simple
    ke_shader_compiler_bgfx
)

target_include_directories(c_demo_04 PRIVATE
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx_shader_compiler/include
)
