add_library(ke_render_bgfx_device STATIC
    src/bgfx_gpu_device.cpp
)

target_compile_definitions(ke_render_bgfx_device PUBLIC KE_RENDER_STATIC)

target_include_directories(ke_render_bgfx_device PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/cpp/render/hal/include
)

target_include_directories(ke_render_bgfx_device PRIVATE
    src
)

find_package(bgfx CONFIG REQUIRED)

target_link_libraries(ke_render_bgfx_device PUBLIC
    ke_render_hal
    bgfx::bgfx
)

target_link_libraries(ke_render_bgfx_device PRIVATE
    bgfx::bx
)

install(TARGETS ke_render_bgfx_device
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
