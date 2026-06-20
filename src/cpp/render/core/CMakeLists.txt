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

set_property(TARGET ke_render_core PROPERTY POSITION_INDEPENDENT_CODE ON)

target_include_directories(ke_render_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_include_directories(ke_render_core PRIVATE
    src
    ${CMAKE_SOURCE_DIR}/src/cpp/render/contract/include
)

target_link_libraries(ke_render_core PUBLIC
    ke_render
    ke_render_frame_packet
    ke_window
    ke_render_contract
    ke_threading
    ke_allocator_malloc
    ke_common
    ke_logger
)

install(TARGETS ke_render_core
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
