add_library(ke_asset_stb_image
    src/stb_image_loader.cpp
)

get_target_property(target_type ke_asset_stb_image TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_asset_stb_image PUBLIC KE_ASSET_STB_IMAGE_STATIC)
else()
    target_compile_definitions(ke_asset_stb_image PRIVATE KE_ASSET_STB_IMAGE_EXPORT)
endif()

target_include_directories(ke_asset_stb_image PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
)

target_include_directories(ke_asset_stb_image PRIVATE
    src
)

# stb is header-only in vcpkg. STB_IMAGE_IMPLEMENTATION is defined in stb_image_loader.cpp; as a
# separate shared library from ke_asset_assimp (which also pulls stb in), each DLL owns its own
# copy of the implementation — no symbol collision.
find_path(STB_INCLUDE_DIR "stb_image.h" REQUIRED)
target_include_directories(ke_asset_stb_image PRIVATE ${STB_INCLUDE_DIR})

target_link_libraries(ke_asset_stb_image PUBLIC
    ke_kernel
    ke_asset
)

install(TARGETS ke_asset_stb_image
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
