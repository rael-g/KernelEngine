add_library(ke_render_bgfx
    src/bgfx_renderer.cpp
    src/geometry_manager.cpp
    src/texture_manager.cpp
    src/lighting_manager.cpp
    src/shadow_pipeline.cpp
    src/post_process_pipeline.cpp
    src/clustered_forward.cpp
)

get_target_property(target_type ke_render_bgfx TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_render_bgfx PUBLIC KE_RENDER_STATIC)
else()
    target_compile_definitions(ke_render_bgfx PRIVATE KE_RENDER_EXPORT)
endif()

target_include_directories(ke_render_bgfx PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
)

target_include_directories(ke_render_bgfx PRIVATE
    src
)

find_package(bgfx CONFIG REQUIRED)

target_link_libraries(ke_render_bgfx PUBLIC
    ke_kernel
    bgfx::bgfx
)

target_link_libraries(ke_render_bgfx PRIVATE
    bgfx::bimg
    bgfx::bx
)

install(TARGETS ke_render_bgfx
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
