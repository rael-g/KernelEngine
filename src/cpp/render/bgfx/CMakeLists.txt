# Purified Assembly Layer: Joins all tiers into a single library while maintaining physical separation
add_library(ke_render_bgfx SHARED
    # Assembly
    src/bgfx_render_factory.cpp
    
    # Core Layer (Agnostic Logic)
    ../core/src/core_renderer.cpp
    ../core/src/geometry_manager.cpp
    ../core/src/texture_manager.cpp
    ../core/src/lighting_manager.cpp
    ../core/src/shadow_pipeline.cpp
    ../core/src/post_process_pipeline.cpp
    ../core/src/clustered_forward.cpp
    ../core/src/shader_provider.cpp
    
    # Device Layer (Bgfx Implementation)
    ../bgfx_device/src/bgfx_gpu_device.cpp
)

find_package(bgfx CONFIG REQUIRED)

target_link_libraries(ke_render_bgfx PUBLIC
    ke_kernel
    bgfx::bgfx
)

target_link_libraries(ke_render_bgfx PRIVATE
    bgfx::bx
)

get_target_property(target_type ke_render_bgfx TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_render_bgfx PUBLIC KE_RENDER_STATIC)
else()
    target_compile_definitions(ke_render_bgfx PRIVATE KE_RENDER_EXPORT)
endif()

# Unified Include Paths
target_include_directories(ke_render_bgfx PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_include_directories(ke_render_bgfx PRIVATE
    src
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/contract/include
    ../core/src
    ../bgfx_device/src
)

install(TARGETS ke_render_bgfx
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
