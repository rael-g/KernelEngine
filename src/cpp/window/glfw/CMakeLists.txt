find_package(glfw3 CONFIG REQUIRED)

add_library(ke_window_glfw
    src/GlfwWindowSystem.cc
)

get_target_property(target_type ke_window_glfw TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_window_glfw PUBLIC KE_WINDOW_STATIC)
else()
    target_compile_definitions(ke_window_glfw PRIVATE KE_WINDOW_EXPORT)
endif()

target_include_directories(ke_window_glfw PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/c/core/include
)

target_link_libraries(ke_window_glfw PUBLIC 
    ke_core
    glfw
)
