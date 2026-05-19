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
    public static MeshHandle DefaultMeshHandle { get; internal set; } = new(0);

    /// <summary>Handle of the built-in white material (handle 0, created by the renderer at init).</summary>
    public static MaterialHandle DefaultMaterialHandle { get; internal set; } = new(0);

    /// <summary>
    /// Registers the MeshComponent with the ECS registry and stores the component ID.
    /// Must be called once per world, before any MeshNode is added to the scene.
    /// </summary>
    internal static void Initialize(IEcsRegistry registry)
    {
        ComponentId = registry.RegisterComponent<MeshComponent>("ke_mesh_renderer");
    }

    // ── Per-instance ──────────────────────────────────────────────────────────

    /// <summary>
    /// GPU mesh handle to render. Defaults to <see cref="DefaultMeshHandle"/> (built-in unit quad).
    /// Set this to a handle returned by <see cref="Renderer.CreateMesh"/> for custom geometry.
    /// </summary>
    public MeshHandle MeshHandle { get; init; } = MeshHandle.None;

    /// <summary>
    /// Material handle to use for rendering. Defaults to <see cref="DefaultMaterialHandle"/> (built-in white).
    /// Set this to a handle returned by <see cref="Renderer.CreateMaterial"/> for custom materials.
    /// </summary>
    public MaterialHandle MaterialHandle { get; init; } = MaterialHandle.None;

    protected override void OnStart()
    {
        if (ComponentId == uint.MaxValue) return;
        var comp = AddComponent<MeshComponent>(ComponentId);
        comp[0] = new MeshComponent
        {
            MeshHandle     = MeshHandle.IsValid     ? MeshHandle     : DefaultMeshHandle,
            MaterialHandle = MaterialHandle.IsValid ? MaterialHandle : DefaultMaterialHandle,
        };
    }
}
