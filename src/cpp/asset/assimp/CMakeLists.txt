add_library(ke_asset_assimp
    src/assimp_loader.cpp
    src/assimp_converter.cpp
    src/texture_decoder.cpp
)

get_target_property(target_type ke_asset_assimp TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_asset_assimp PUBLIC KE_ASSET_ASSIMP_STATIC)
else()
    target_compile_definitions(ke_asset_assimp PRIVATE KE_ASSET_ASSIMP_EXPORT)
endif()

target_include_directories(ke_asset_assimp PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/c/asset/include
)

target_include_directories(ke_asset_assimp PRIVATE
    src
)

find_package(assimp CONFIG REQUIRED)

target_link_libraries(ke_asset_assimp PUBLIC
    ke_asset
    ke_logger
    assimp::assimp
)

install(TARGETS ke_asset_assimp
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
