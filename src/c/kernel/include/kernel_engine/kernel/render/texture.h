#ifndef KERNEL_ENGINE_KERNEL_RENDER_TEXTURE_H_
#define KERNEL_ENGINE_KERNEL_RENDER_TEXTURE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Stable opaque handle to a GPU texture. Returned by ke_render::create_texture_rgba.
    typedef uint32_t ke_texture_handle;

#define KE_TEXTURE_HANDLE_INVALID ((ke_texture_handle)UINT32_MAX)

    /// @brief Handle 0 is always the built-in 1×1 white texture created at renderer init.
#define KE_TEXTURE_HANDLE_WHITE ((ke_texture_handle)0)

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_RENDER_TEXTURE_H_
