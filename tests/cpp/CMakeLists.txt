find_package(GTest CONFIG REQUIRED)
find_package(assimp CONFIG REQUIRED)

add_executable(test_threading
    test_threading.cpp
)

target_include_directories(test_threading PRIVATE
    ${CMAKE_SOURCE_DIR}/src/cpp/threading/include
)

target_link_libraries(test_threading PRIVATE
    ke_threading
    GTest::gtest_main
)

add_executable(test_asset_logic
    test_asset_logic.cpp
    ../../src/cpp/asset/assimp/src/assimp_converter.cpp
    ../../src/cpp/asset/assimp/src/texture_decoder.cpp
)

target_include_directories(test_asset_logic PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/asset/include
    ${CMAKE_SOURCE_DIR}/src/cpp/asset/assimp/src
)

target_link_libraries(test_asset_logic PRIVATE
    ke_asset
    ke_logger
    ke_allocator_malloc
    assimp::assimp
    GTest::gtest_main
)

gtest_discover_tests(test_threading)
gtest_discover_tests(test_asset_logic)
