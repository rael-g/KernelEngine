add_executable(c_demo_04
    main.c
)

target_link_libraries(c_demo_04 PRIVATE
    ke_core
    ke_shader_compiler_bgfx
)

target_include_directories(c_demo_04 PRIVATE 
    ${CMAKE_SOURCE_DIR}/src/c/core/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx/include
)
