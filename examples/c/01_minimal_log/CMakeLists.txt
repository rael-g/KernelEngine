add_executable(c_demo_01
    main.c
)

target_link_libraries(c_demo_01 PRIVATE
    ke_allocator_malloc
    ke_logger_simple
)
