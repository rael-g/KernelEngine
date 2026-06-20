#ifndef KERNEL_ENGINE_RENDER_LIGHT_H_
#define KERNEL_ENGINE_RENDER_LIGHT_H_

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

    /// @brief Omnidirectional point light for ke_render::set_point_lights.
    typedef struct ke_point_light
    {
        float pos_x, pos_y, pos_z; ///< World-space position
        float radius;              ///< Influence radius — attenuation reaches zero at this distance
        float r, g, b;             ///< Light color (linear)
        float intensity;           ///< Multiplier applied to color
    } ke_point_light;

    /// @brief Cone-shaped spot light for ke_render::set_spot_lights.
    typedef struct ke_spot_light
    {
        float pos_x, pos_y, pos_z; ///< World-space position
        float range;               ///< Attenuation range — intensity reaches zero at this distance
        float dir_x, dir_y, dir_z; ///< Direction the cone points toward (world space, normalized)
        float inner_angle;         ///< Inner cone half-angle in radians (full intensity inside)
        float r, g, b;             ///< Light color (linear)
        float intensity;           ///< Multiplier applied to color
        float outer_angle;         ///< Outer cone half-angle in radians (zero intensity outside)
    } ke_spot_light;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_LIGHT_H_
