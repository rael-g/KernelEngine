add_library(ke_render_core SHARED
    src/core_renderer.cpp
    src/geometry_manager.cpp
    src/texture_manager.cpp
    src/lighting_manager.cpp
    src/shadow_pipeline.cpp
    src/post_process_pipeline.cpp
    src/clustered_forward.cpp
    src/shader_provider.cpp
    src/frame_submitter.cpp
    src/render_graph_impl.cpp
)

# render/core is a backend support library used by render plugins (bgfx, future Vulkan/DX12, ...).
# It exposes no public C ABI of its own — callers include the C++ headers from include/ + src/
# directly. The previous public surface (the 5 *_describe factories) was deleted along with the
# C++ render systems, which were ported to pure-managed C# in KernelEngine.Framework.

target_compile_definitions(ke_render_core PRIVATE KE_RENDER_CORE_EXPORT)

target_include_directories(ke_render_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
)

target_include_directories(ke_render_core PRIVATE
    src
    ${CMAKE_SOURCE_DIR}/src/cpp/render/contract/include
)

target_link_libraries(ke_render_core PUBLIC
    ke_kernel
    ke_render_contract
    ke_threading
)

install(TARGETS ke_render_core
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
