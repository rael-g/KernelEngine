using KernelEngine.Render;


namespace KernelEngine.Framework;

/// <summary>
/// Skybox node — provides the cubemap rendered behind the scene and used as the
/// IBL environment by PBR materials. Only the first Skybox node wins per frame.
/// </summary>
[GeneratedNodeComponent(typeof(SkyboxComponent), SkyboxComponent.Name)]
public partial class Skybox : Node3D
{
    public partial TextureHandle CubemapHandle { get; set; }
}
