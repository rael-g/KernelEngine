using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node that renders a mesh via the ECS mesh render system.
/// Set <see cref="MeshHandle"/> and <see cref="MaterialHandle"/> before adding to the scene,
/// or leave as default to use the built-in unit quad with a white material.
/// </summary>
public class MeshNode : Node
{
    // ── ECS registration (shared across all MeshNode instances) ──────────────

    public static uint ComponentId { get; private set; } = uint.MaxValue;

    /// <summary>Handle of the built-in unit quad mesh (handle 0, created by the renderer at init).</summary>
    public static uint DefaultMeshHandle { get; internal set; } = 0;

    /// <summary>Handle of the built-in white material (handle 0, created by the renderer at init).</summary>
    public static uint DefaultMaterialHandle { get; internal set; } = 0;

    /// <summary>
    /// Registers the MeshComponent with the ECS registry and stores the component ID.
    /// Must be called once per world, before any MeshNode is added to the scene.
    /// </summary>
    internal static void Initialize(EcsRegistry registry)
    {
        ComponentId = registry.RegisterComponent<MeshComponent>("ke_mesh_renderer");
    }

    // ── Per-instance ──────────────────────────────────────────────────────────

    /// <summary>
    /// GPU mesh handle to render. Defaults to <see cref="DefaultMeshHandle"/> (built-in unit quad).
    /// Set this to a handle returned by <see cref="Renderer.CreateMesh"/> for custom geometry.
    /// </summary>
    public uint MeshHandle { get; init; } = uint.MaxValue;

    /// <summary>
    /// Material handle to use for rendering. Defaults to <see cref="DefaultMaterialHandle"/> (built-in white).
    /// Set this to a handle returned by <see cref="Renderer.CreateMaterial"/> for custom materials.
    /// </summary>
    public uint MaterialHandle { get; init; } = uint.MaxValue;

    protected override void OnStart()
    {
        if (ComponentId == uint.MaxValue) return;
        ref var comp = ref AddComponent<MeshComponent>(ComponentId);
        comp = new MeshComponent
        {
            MeshHandle     = MeshHandle     != uint.MaxValue ? MeshHandle     : DefaultMeshHandle,
            MaterialHandle = MaterialHandle != uint.MaxValue ? MaterialHandle : DefaultMaterialHandle,
        };
    }
}
