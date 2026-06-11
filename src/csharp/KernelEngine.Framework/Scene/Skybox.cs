using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Skybox node — provides the cubemap rendered behind the scene and used as
/// the IBL environment by PBR materials. Only the first Skybox node in the
/// tree is consumed per frame; spawning multiple is allowed but only one wins.
/// </summary>
public class Skybox : Node
{
    private SkyboxComponent _state;

    public TextureHandle CubemapHandle
    {
        get => _state.CubemapHandle;
        set { _state.CubemapHandle = value; if (IsBound) Tree!.SetSkybox(Entity, _state); }
    }

    protected internal override void OnBind(Tree tree) => tree.SetSkybox(Entity, _state);
}
