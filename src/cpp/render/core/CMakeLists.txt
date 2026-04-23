add_library(ke_render_core STATIC
    src/core_renderer.cpp
    src/geometry_manager.cpp
    src/texture_manager.cpp
    src/lighting_manager.cpp
    src/shadow_pipeline.cpp
    src/post_process_pipeline.cpp
    src/clustered_forward.cpp
    src/shader_provider.cpp
)

# No need for KE_RENDER_EXPORT if it's static
target_compile_definitions(ke_render_core PUBLIC KE_RENDER_STATIC)

target_include_directories(ke_render_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/hal/include
)

target_include_directories(ke_render_core PRIVATE
    src
)

target_link_libraries(ke_render_core PUBLIC
    ke_kernel
    ke_render_hal
)

install(TARGETS ke_render_core
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
