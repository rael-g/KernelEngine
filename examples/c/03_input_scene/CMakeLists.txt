add_executable(c_example_03_input_scene
    main.c
)

target_link_libraries(c_example_03_input_scene PRIVATE
    ke_kernel
    ke_window_glfw
    ke_render_bgfx
)

target_include_directories(c_example_03_input_scene PRIVATE 
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/window/glfw/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx/include
)
