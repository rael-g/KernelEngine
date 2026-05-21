add_library(ke_window_glfw SHARED
    src/window_glfw_factory.cpp
)

find_package(glfw3 CONFIG REQUIRED)

target_link_libraries(ke_window_glfw
    PUBLIC
        ke_kernel
    PRIVATE
        ke_window_core
        ke_window_glfw_device
        glfw
)

get_target_property(target_type ke_window_glfw TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_window_glfw PUBLIC KE_WINDOW_STATIC)
else()
    target_compile_definitions(ke_window_glfw PRIVATE KE_WINDOW_EXPORT)
endif()

target_include_directories(ke_window_glfw PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

install(TARGETS ke_window_glfw
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
