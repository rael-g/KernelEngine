# Dev-only platform abstraction.
# Each backend is a separate plugin. Only build the impls valid for the host OS;
# selection at runtime is done by the application via DI in C# (Program.cs).

if (WIN32)
    add_subdirectory(win32)
endif()

if (UNIX AND NOT APPLE)
    add_subdirectory(posix)
endif()

if (APPLE)
    add_subdirectory(posix) # macOS uses pthread_setname_np too
endif()
