using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using RenderCoreNative = KernelEngine.Render.Core.Native.NativeMethods;

namespace KernelEngine.Render.Core;

public record DefaultRenderSystems(
    MeshRenderSystem Mesh,
    LightRenderSystem Light,
    CameraRenderSystem Camera,
    ShadowRenderSystem Shadow,
    SkyboxRenderSystem Skybox);

public static unsafe class RenderCore
{
    /// <summary>
    /// Registers the default render systems into the native world and returns their managed wrappers.
    /// </summary>
    public static DefaultRenderSystems RegisterDefaultSystems(
        World world,
        IRenderer renderer,
        uint meshCid,
        uint transformCid,
        uint lightCid,
        uint pointCid,
        uint spotCid,
        uint cameraCid,
        uint skyboxCid)
    {
        ke_system_params meshParams;
        RenderCoreNative.render_core_mesh_system_describe(meshCid, transformCid, &meshParams);
        
        ke_system_params lightParams;
        RenderCoreNative.render_core_light_system_describe(lightCid, pointCid, spotCid, transformCid, &lightParams);
        
        ke_system_params cameraParams;
        RenderCoreNative.render_core_camera_system_describe(cameraCid, transformCid, &cameraParams);
        
        ke_system_params shadowParams;
        RenderCoreNative.render_core_shadow_system_describe(lightCid, meshCid, transformCid, &shadowParams);
        
        ke_system_params skyboxParams;
        RenderCoreNative.render_core_skybox_system_describe(skyboxCid, &skyboxParams);

        var mesh = new MeshRenderSystem(meshParams);
        var light = new LightRenderSystem(lightParams);
        var camera = new CameraRenderSystem(cameraParams);
        var shadow = new ShadowRenderSystem(shadowParams);
        var skybox = new SkyboxRenderSystem(skyboxParams);

        // Add them to the managed scheduler
        world.AddSystem(mesh);
        world.AddSystem(light);
        world.AddSystem(camera);
        world.AddSystem(shadow);
        world.AddSystem(skybox);

        return new DefaultRenderSystems(mesh, light, camera, shadow, skybox);
    }
}
