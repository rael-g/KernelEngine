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
    src/render_core.cpp
    src/mesh_system.cpp
    src/light_system.cpp
    src/camera_system.cpp
    src/shadow_system.cpp
    src/skybox_system.cpp
)

target_compile_definitions(ke_render_core PRIVATE KE_RENDER_CORE_EXPORT)

target_include_directories(ke_render_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/contract/include
)

target_include_directories(ke_render_core PRIVATE
    src
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

install(DIRECTORY include/ DESTINATION include)
