#ifndef KERNEL_ENGINE_RENDER_COMPONENTS_H_
#define KERNEL_ENGINE_RENDER_COMPONENTS_H_

#include <kernel_engine/common/math.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/spatial/transform.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** [node:Camera,base:Node3D] Scene node that drives the per-frame view/projection. The first entity with a Camera in the ECS becomes the active camera. */
    typedef struct ke_camera_component
    {
        float   fov; ///< [default:60]
        float   near_plane; ///< [default:0.1]
        float   far_plane; ///< [default:1000]
        float   orthographic_size; ///< [default:5]
        uint8_t orthographic; ///< [bool]
    } ke_camera_component;

    /** [node:DirectionalLight,base:Node3D] Directional light node. Init properties feed the per-frame light state the renderer consumes. */
    typedef struct ke_directional_light_component
    {
        ke_vec3 direction; ///< [default:0.2 1 0.5]
        ke_vec3 color; ///< [default:1 1 1] Linear RGB.
        float   intensity; ///< [default:1]
        ke_vec3 ambient; ///< [default:0.2 0.2 0.2]
    } ke_directional_light_component;

    /** [node:PointLight,base:Node3D] Point light node — emits light in all directions from this entity's world position. */
    typedef struct ke_point_light_component
    {
        ke_vec3 color; ///< [default:1 1 1] Linear RGB.
        float   intensity; ///< [default:1]
        float   radius; ///< [default:10]
    } ke_point_light_component;

    /** [node:SpotLight,base:Node3D] Spot light node — emits a cone of light from this entity's world position. */
    typedef struct ke_spot_light_component
    {
        ke_vec3 direction; ///< [default:0 -1 0]
        ke_vec3 color; ///< [default:1 1 1] Linear RGB.
        float   intensity; ///< [default:1]
        float   range; ///< [default:20]
        float   inner_angle; ///< [default:25]
        float   outer_angle; ///< [default:35]
    } ke_spot_light_component;

    /** [node:AmbientLight,base:Node3D] Scene-wide ambient light node. First entity with this component wins. */
    typedef struct ke_ambient_light_component
    {
        ke_vec3 color; ///< [default:0.05 0.05 0.05]
    } ke_ambient_light_component;

    /// [node:Skybox,base:Node3D]
    /// Environment cubemap driving both the skybox and image-based lighting. Only
    /// the first entity carrying one wins per frame.
    typedef struct ke_skybox_component
    {
        /// [name:cubemap_handle]
        ke_texture_handle cubemap;
    } ke_skybox_component;

    /// [node:MeshRenderer,base:Node3D]
    /// Renders a mesh with a material. `mesh`/`material` double as output:
    /// the native "render.mesh.resolve" system (KE_PHASE_UPDATE,
    /// src/zig/render/service/src/mesh_resolve.zig) fills them whenever
    /// `primitive` names a known shape and/or the surface fields below have not
    /// already resolved to a valid handle. A caller holding real handles just
    /// writes them and leaves `primitive` empty — the resolve system only acts
    /// where a handle is still invalid, so the two paths never conflict.
    typedef struct ke_mesh_component
    {
        /// [name:mesh_handle]
        ke_mesh_handle     mesh;
        /// [name:material_handle]
        ke_material_handle material;
        /// [idiom,name:mesh] Resolved by the scene loader's property-apply path into
        /// `mesh`; a node authoring it directly would have the value overwritten.
        char               primitive[32];

        ke_vec4  base_color; ///< [default:1 1 1 1,name:color]
        float    roughness; ///< [default:1]
        uint32_t alpha_mode; ///< ke_alpha_mode. [default:0]
        float    alpha_cutoff; ///< [default:0.5]
        float    ior; ///< [default:1.5]
        float    distortion_strength; ///< [default:0.05]
    } ke_mesh_component;

    /// [node:Sprite2D,base:Node2D]
    /// A textured quad in the plane. Everything that makes one sprite differ from
    /// another lives here rather than in a mesh a scene happened to author beside
    /// it: which image, which rectangle of it, how big, around what point, and
    /// mirrored on which axis. The native "render.sprite2d.resolve" system turns
    /// that into the geometry and material the render passes already consume, so a
    /// sprite is a node with data in every language instead of a name for a quad.
    typedef struct ke_sprite2d_component
    {
        /// Image to sample. Empty draws the plain tinted quad.
        char     texture[128];
        /// Rectangle of the image to draw, in normalized coordinates: x, y, width,
        /// height. The default is the whole image, so an unauthored sprite is not
        /// an atlas lookup that happens to land on nothing.
        ke_vec4  region; ///< [default:0 0 1 1]
        /// Size in world units. Multiplies the node's scale rather than replacing
        /// it: how big the sprite is and how big the node is are different
        /// questions, and only the first belongs to the image.
        ke_vec2  size; ///< [default:1 1]
        /// Point of the quad the node's origin sits on, in normalized coordinates.
        /// The default centres it; 0,0 is the bottom-left corner.
        ke_vec2  pivot; ///< [default:0.5 0.5]
        uint8_t  flip_h; ///< [bool]
        uint8_t  flip_v; ///< [bool]
        /// Multiplies the sampled image. Linear RGBA.
        ke_vec4  color; ///< [default:1 1 1 1]
        uint32_t alpha_mode; ///< ke_alpha_mode. [default:0]
        float    alpha_cutoff; ///< [default:0.5]

        /// [idiom] The image resolved from `texture`, assigned by the resolve
        /// system. Authoring it would name a texture the renderer does not hold.
        ke_texture_handle texture_handle;

        /// [idiom] Whether the quad this sprite draws through has been attached.
        /// Set by the resolve system once it has; authoring it would claim
        /// geometry the entity does not carry.
        uint8_t           attached; ///< [bool]
    } ke_sprite2d_component;

#define KE_COMPONENT_NAME_SPRITE_2D         "sprite2d"
#define KE_COMPONENT_NAME_CAMERA            "camera"
#define KE_COMPONENT_NAME_DIRECTIONAL_LIGHT "directional_light"
#define KE_COMPONENT_NAME_POINT_LIGHT       "point_light"
#define KE_COMPONENT_NAME_SPOT_LIGHT        "spot_light"
#define KE_COMPONENT_NAME_AMBIENT_LIGHT     "ambient_light"
#define KE_COMPONENT_NAME_SKYBOX            "skybox"
#define KE_COMPONENT_NAME_MESH              "mesh"

#ifdef __cplusplus
}
#endif

#endif
