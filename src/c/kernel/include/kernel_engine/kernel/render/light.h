#ifndef KERNEL_ENGINE_KERNEL_RENDER_LIGHT_H_
#define KERNEL_ENGINE_KERNEL_RENDER_LIGHT_H_

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Directional light parameters for ke_render::set_directional_light.
    typedef struct ke_directional_light
    {
        float dir_x, dir_y, dir_z; ///< Direction toward the light source (world space, normalized)
        float r, g, b;             ///< Light color
        float intensity;           ///< Multiplier applied to color
    } ke_directional_light;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_RENDER_LIGHT_H_
