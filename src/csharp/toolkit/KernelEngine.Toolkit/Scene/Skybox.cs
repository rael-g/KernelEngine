using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Skybox node — provides the cubemap rendered behind the scene and used as the
/// IBL environment by PBR materials. Only the first Skybox node wins per frame.
/// </summary>
public class Skybox : Node
{
    private SkyboxComponent _state;

    public TextureHandle CubemapHandle
    {
        get => _state.CubemapHandle;
        set { _state.CubemapHandle = value; if (IsBound) NodeWorld!.Set(Entity, _state); }
    }

    protected internal override void OnBind(NodeWorld nodeWorld) => nodeWorld.Set(Entity, _state);
}
