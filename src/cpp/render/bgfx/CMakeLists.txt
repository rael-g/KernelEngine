find_package(bgfx CONFIG REQUIRED)
find_package(glm CONFIG REQUIRED)

add_library(ke_render_bgfx
    src/bgfx_render_system.cc
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

target_link_libraries(ke_render_bgfx PUBLIC 
    ke_kernel
    bgfx::bgfx
    bgfx::bx
    bgfx::bimg
    glm::glm
)

install(TARGETS ke_render_bgfx
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

# Install the kernel_engine folder into include/
install(DIRECTORY include/kernel_engine DESTINATION include)
