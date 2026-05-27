using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A Tree node that renders a mesh via the ECS mesh render system.
/// Set <see cref="MeshHandle"/> and <see cref="MaterialHandle"/> before adding to the Tree,
/// or leave as default to use the built-in unit quad with a white material.
/// </summary>
public class MeshRenderer : Node
{
    /// <summary>Handle of the built-in unit quad mesh (handle 0, created by the renderer at init).</summary>
    public static MeshHandle DefaultMeshHandle { get; internal set; } = new(0);

    /// <summary>Handle of the built-in white material (handle 0, created by the renderer at init).</summary>
    public static MaterialHandle DefaultMaterialHandle { get; internal set; } = new(0);

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

    protected override void Start()
    {
        if (World == null) return;

        // Retain managed resources so they stay alive while the node references them. Until Node
        // gets an OnDestroy hook, the retain isn't paired with a Release here — resources live
        // for the node's lifetime (acceptable for "create once at OnReady" usage; a future node-
        // lifecycle slice pairs this with a release on node destruction).
        Mesh?.Retain();
        Material?.Retain();

        var meshHandle = Mesh?.Handle ?? (MeshHandle.IsValid ? MeshHandle : DefaultMeshHandle);
        var materialHandle = Material?.Handle ?? (MaterialHandle.IsValid ? MaterialHandle : DefaultMaterialHandle);

        var cid = World.GetOrRegisterComponentId<MeshComponent>("ke_mesh_renderer");
        var comp = AddComponent<MeshComponent>(cid);
        comp[0] = new MeshComponent { MeshHandle = meshHandle, MaterialHandle = materialHandle };
    }
}
