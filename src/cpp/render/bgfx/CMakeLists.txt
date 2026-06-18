# Purified Assembly Layer: Joins all tiers into a single library
add_library(ke_render_bgfx SHARED
    # Assembly
    src/bgfx_render_factory.cpp
)

find_package(bgfx CONFIG REQUIRED)

target_link_libraries(ke_render_bgfx PRIVATE
    ke_render_core
    ke_render_bgfx_device
    ke_threading
    ke_allocator_malloc
    bgfx::bgfx
    bgfx::bx
)

target_compile_definitions(ke_render_bgfx PRIVATE KE_RENDER_BGFX_EXPORT)

# UNIFIED INCLUDE SEARCH PATHS
target_include_directories(ke_render_bgfx PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_include_directories(ke_render_bgfx PRIVATE
    src
    ${CMAKE_SOURCE_DIR}/src/cpp/render/contract/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/core/include
    ${CMAKE_SOURCE_DIR}/src/cpp/render/core/src
)

install(TARGETS ke_render_bgfx
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
