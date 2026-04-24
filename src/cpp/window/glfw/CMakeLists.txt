# Assembly Layer for Window (GLFW implementation)
# Joins all tiers into a single library for Windows linker consistency
add_library(ke_window_glfw SHARED
    # Assembly
    src/window_glfw_factory.cpp
    
    # Core Layer (Agnostic Logic)
    ../core/src/window_core.cpp
    
    # Device Layer (GLFW Implementation)
    ../glfw_device/src/glfw_window_device.cpp
)

find_package(glfw3 CONFIG REQUIRED)

target_link_libraries(ke_window_glfw 
    PUBLIC 
        ke_kernel
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

target_include_directories(ke_window_glfw PRIVATE
    src
    ${CMAKE_SOURCE_DIR}/src/cpp/window/contract/include
    ${CMAKE_SOURCE_DIR}/src/cpp/window/core/include
    ../core/src
    ../glfw_device/src
)

install(TARGETS ke_window_glfw
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
