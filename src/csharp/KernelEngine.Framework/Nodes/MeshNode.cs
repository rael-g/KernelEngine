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
    /// High-level mesh resource. When set, the node retains a reference for its lifetime and uses
    /// its handle. Falls back to <see cref="MeshHandle"/> / <see cref="DefaultMeshHandle"/>.
    /// </summary>
    public Mesh? Mesh { get; init; }

    /// <summary>
    /// High-level material resource. When set, the node retains a reference for its lifetime and
    /// uses its handle. Falls back to <see cref="MaterialHandle"/> / <see cref="DefaultMaterialHandle"/>.
    /// </summary>
    public Material? Material { get; init; }

    /// <summary>Raw GPU mesh handle (escape hatch / backward compat). Prefer <see cref="Mesh"/>.</summary>
    public MeshHandle MeshHandle { get; init; } = MeshHandle.None;

    /// <summary>Raw GPU material handle (escape hatch / backward compat). Prefer <see cref="Material"/>.</summary>
    public MaterialHandle MaterialHandle { get; init; } = MaterialHandle.None;

    protected override void OnStart()
    {
        if (ComponentId == uint.MaxValue) return;

        // Retain managed resources so they stay alive while the node references them. Until Node
        // gets an OnDestroy hook, the retain isn't paired with a Release here — resources live
        // for the node's lifetime (acceptable for "create once at OnReady" usage; a future node-
        // lifecycle slice pairs this with a release on node destruction).
        Mesh?.Retain();
        Material?.Retain();

        var meshHandle = Mesh?.Handle ?? (MeshHandle.IsValid ? MeshHandle : DefaultMeshHandle);
        var materialHandle = Material?.Handle ?? (MaterialHandle.IsValid ? MaterialHandle : DefaultMaterialHandle);

        var comp = AddComponent<MeshComponent>(ComponentId);
        comp[0] = new MeshComponent { MeshHandle = meshHandle, MaterialHandle = materialHandle };
    }
}
