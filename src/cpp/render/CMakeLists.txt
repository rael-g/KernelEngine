# Agnostic Contract layer
add_subdirectory(contract)

# Concrete Driver Implementation
add_subdirectory(bgfx_device)

# Agnostic Rendering Logic
# Consolidado em bgfx por questões de linkagem no Windows
add_subdirectory(bgfx)
add_subdirectory(bgfx_shader_compiler)
