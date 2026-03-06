find_package(assimp CONFIG REQUIRED)
find_path(STB_INCLUDE_DIRS "stb_image.h")

add_library(ke_asset_loader_assimp
    src/asset_loader_assimp.cc
)

get_target_property(target_type ke_asset_loader_assimp TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_asset_loader_assimp PUBLIC KE_ASSET_ASSIMP_STATIC)
else()
    target_compile_definitions(ke_asset_loader_assimp PRIVATE KE_ASSET_ASSIMP_EXPORT)
endif()

target_include_directories(ke_asset_loader_assimp PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
)

target_include_directories(ke_asset_loader_assimp PRIVATE
    ${STB_INCLUDE_DIRS}
)

target_link_libraries(ke_asset_loader_assimp PUBLIC
    ke_kernel
    assimp::assimp
)

install(TARGETS ke_asset_loader_assimp
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/kernel_engine DESTINATION include)
