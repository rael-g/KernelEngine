find_package(GTest CONFIG REQUIRED)

add_executable(test_ke_kernel
    test_allocator.cpp
    test_hash_map.cpp
    test_message_pipe.cpp
    test_ecs.cpp
    test_world.cpp
)

target_link_libraries(test_ke_kernel PRIVATE
    ke_kernel
    GTest::gtest_main
)

target_include_directories(test_ke_kernel PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
)

set_target_properties(test_ke_kernel PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

include(GoogleTest)
gtest_discover_tests(test_ke_kernel)

if(KE_COVERAGE)
    enable_coverage(test_ke_kernel)
endif()
