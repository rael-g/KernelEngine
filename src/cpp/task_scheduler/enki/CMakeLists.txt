find_package(enkiTS CONFIG REQUIRED)

add_library(ke_task_scheduler_enki
    src/enki_task_scheduler.cpp
)

get_target_property(target_type ke_task_scheduler_enki TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_task_scheduler_enki PUBLIC KE_TASK_SCHEDULER_STATIC)
else()
    target_compile_definitions(ke_task_scheduler_enki PRIVATE KE_TASK_SCHEDULER_EXPORT)
endif()

target_include_directories(ke_task_scheduler_enki PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
)

target_include_directories(ke_task_scheduler_enki PRIVATE
    src
)

target_link_libraries(ke_task_scheduler_enki PUBLIC 
    ke_kernel 
    enkiTS::enkiTS
)

install(TARGETS ke_task_scheduler_enki
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
