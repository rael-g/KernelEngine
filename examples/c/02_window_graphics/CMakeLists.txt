add_executable(c_example_02_graphics
    main.c
)

target_link_libraries(c_example_02_graphics PRIVATE
    ke_core
    ke_window_glfw
    ke_render_bgfx
)

target_include_directories(c_example_02_graphics PRIVATE 
    ${CMAKE_SOURCE_DIR}/src/c/core/include
    ${CMAKE_SOURCE_DIR}/src/cpp/window/glfw/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/bgfx/include
)
