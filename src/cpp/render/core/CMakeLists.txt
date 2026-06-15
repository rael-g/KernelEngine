add_library(ke_render_core STATIC
    src/core_renderer.cpp
    src/geometry_manager.cpp
    src/texture_manager.cpp
    src/lighting_manager.cpp
    src/shadow_pipeline.cpp
    src/post_process_pipeline.cpp
    src/clustered_forward.cpp
    src/shader_provider.cpp
    src/render_graph_impl.cpp
)

# render/core is a backend support library used by render plugins (bgfx, future Vulkan/DX12, ...).
# It exposes no public C ABI of its own — callers include the C++ headers from include/ + src/
# directly. Built STATIC: the only consumers are render plugins (which embed it into their own
# shared library) and the C++ test suite (which links it directly). A STATIC lib avoids needing
# dllexport on every class, which is what the previous SHARED build required.
set_property(TARGET ke_render_core PROPERTY POSITION_INDEPENDENT_CODE ON)

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
    ke_window
    ke_render_contract
    ke_threading
)

install(TARGETS ke_render_core
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
