set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)
include("${CMAKE_CURRENT_LIST_DIR}/zig-common.cmake")

set(CMAKE_C_FLAGS_INIT "-target x86_64-windows-gnu")
set(CMAKE_CXX_FLAGS_INIT "-target x86_64-windows-gnu")
foreach(kind EXE SHARED MODULE)
  set(CMAKE_${kind}_LINKER_FLAGS_INIT "-target x86_64-windows-gnu")
endforeach()
