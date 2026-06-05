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
    /// Read once in <see cref="Start"/>; changing after Start has no effect on the live ECS slot
    /// (live mesh swap is a future enhancement).
    /// </summary>
    public Mesh? Mesh { get; set; }

    /// <summary>
    /// High-level material resource. When set, the node retains a reference for its lifetime and
    /// uses its handle. Falls back to <see cref="MaterialHandle"/> / <see cref="DefaultMaterialHandle"/>.
    /// Read once in <see cref="Start"/>; changing after Start has no effect on the live ECS slot.
    /// </summary>
    public Material? Material { get; set; }

    /// <summary>Raw GPU mesh handle (escape hatch / backward compat). Prefer <see cref="Mesh"/>.</summary>
    public MeshHandle MeshHandle { get; init; } = MeshHandle.None;

    /// <summary>Raw GPU material handle (escape hatch / backward compat). Prefer <see cref="Material"/>.</summary>
    public MaterialHandle MaterialHandle { get; init; } = MaterialHandle.None;

    protected override void Start()
    {
        if (World == null) return;

        // Phase 5.3: resolve scene-authored Material/Mesh references from the bag (option C
        // of plan §5b). Inline material colors live as a single MaterialBaseColor vec4;
        // mesh paths like "res://primitives/quad" map to the built-in default handle, so the
        // common Pong case (every Sprite2D uses the quad) needs no real path resolver.
        if (Material is null && Properties.TryGetVector4("MaterialBaseColor", out var color))
        {
            if (FrameworkBackends.Resources is ResourceManager rm)
                Material = rm.CreateMaterialAsync(color).GetAwaiter().GetResult();
        }
        // Mesh string property: today only "res://primitives/quad" is supported (== default).
        // Other primitives (cube/sphere) and arbitrary res:// paths land in S8 with the full
        // ResourceResolver port — see plan §7a.

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
