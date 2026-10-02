set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
include("${CMAKE_CURRENT_LIST_DIR}/zig-common.cmake")

set(CMAKE_C_FLAGS_INIT "-idirafter /usr/include")
set(CMAKE_CXX_FLAGS_INIT "-idirafter /usr/include")
foreach(kind EXE SHARED MODULE)
  set(CMAKE_${kind}_LINKER_FLAGS_INIT "-L/usr/lib/x86_64-linux-gnu -L/usr/lib")
endforeach()

set(CMAKE_LIBRARY_ARCHITECTURE "x86_64-linux-gnu")
