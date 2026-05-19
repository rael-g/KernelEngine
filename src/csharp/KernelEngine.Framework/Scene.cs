using System.Numerics;
using System.Runtime.InteropServices;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Scene graph facade built on top of the ECS world.
/// Manages a hierarchy of <see cref="Node"/> instances backed by ECS entities.
/// Node/scene are framework-level concepts; the ECS world itself knows only
/// entities, components, and systems.
/// </summary>
public sealed unsafe class Scene
{
    private readonly World _world;
    private readonly Node  _root;

    internal Scene(World world)
    {
        _world = world;
        var rootEntity = CreateEntityWithHierarchy("Root", KE_ENTITY_INVALID);
        _root = new Node(rootEntity, world, "Root");
    }

    private const ulong KE_ENTITY_INVALID = 0;

    /// <summary>The implicit root node of this scene.</summary>
    public Node Root => _root;

    // ── High-level add ────────────────────────────────────────────────────────

    /// <summary>
    /// Creates a plain (non-scripted) node as a child of <paramref name="parent"/>
    /// (defaults to <see cref="Root"/>).
    /// </summary>
    public Node AddNode(string name, Node? parent = null)
    {
        var parentEntity = parent?.Entity ?? _root.Entity;
        var entity = CreateEntityWithHierarchy(name, parentEntity);
        return new Node(entity, _world, name);
    }

    /// <summary>
    /// Creates a scripted node as a child of <paramref name="parent"/>
    /// (defaults to <see cref="Root"/>). <see cref="Node.OnStart"/> and
    /// <see cref="Node.OnUpdate"/> will be called by the built-in ScriptSystem.
    /// </summary>
    public T AddNode<T>(T node, string name, Node? parent = null) where T : Node
    {
        var parentEntity = parent?.Entity ?? _root.Entity;
        var entity = CreateEntityWithHierarchy(name, parentEntity);
        node.Initialize(entity, _world, name);
        node.RegisterScript();
        return node;
    }

    // ── Destruction ───────────────────────────────────────────────────────────

    /// <summary>
    /// Destroys a node (and all its descendants) and removes it from the scripting registry.
    /// Do not use <paramref name="node"/> after this call.
    /// </summary>
    public void DestroyNode(Node node)
    {
        Node.Unregister(node.Entity);
        DestroyEntityRecursive(node.Entity);
    }

    // ── Entity/hierarchy management ───────────────────────────────────────────

    /// <summary>
    /// Creates an ECS entity initialised with Transform, Hierarchy, and Name components,
    /// and links it into the parent's child list.
    /// </summary>
    private ulong CreateEntityWithHierarchy(string name, ulong parent)
    {
        var reg    = _world.Registry;
        var entity = reg.CreateEntity();

        // Transform — default: origin, identity rotation, unit scale
        ref var t = ref *reg.AddComponentRaw<TransformComponent>(entity, _world.TransformComponentId);
        t = new TransformComponent
        {
            Position    = Vector3.Zero,
            Rotation    = Quaternion.Identity,
            Scale       = Vector3.One,
            WorldMatrix = System.Numerics.Matrix4x4.Identity,
        };

        // Hierarchy — link to parent, no children yet
        ref var h = ref *reg.AddComponentRaw<HierarchyComponent>(entity, _world.HierarchyComponentId);
        h = new HierarchyComponent { Parent = parent };

        // Name
        ref var n = ref *reg.AddComponentRaw<NameComponent>(entity, _world.NameComponentId);
        SetName(ref n, name);

        // Prepend entity into parent's child list (O(1) doubly-linked prepend)
        if (parent != KE_ENTITY_INVALID)
        {
            var ph = reg.GetComponentRaw<HierarchyComponent>(parent, _world.HierarchyComponentId);
            if (ph != null)
            {
                h.NextSibling = ph->FirstChild;
                if (ph->FirstChild != KE_ENTITY_INVALID)
                {
                    var sib = reg.GetComponentRaw<HierarchyComponent>(ph->FirstChild, _world.HierarchyComponentId);
                    if (sib != null) sib->PrevSibling = entity;
                }
                ph->FirstChild = entity;
            }
        }

        return entity;
    }

    /// <summary>Recursively destroys an entity and all its descendants, unlinking from parent.</summary>
    private void DestroyEntityRecursive(ulong entity)
    {
        var reg = _world.Registry;
        var h   = reg.GetComponentRaw<HierarchyComponent>(entity, _world.HierarchyComponentId);
        if (h == null) return;

        // Destroy children first (depth-first)
        var child = h->FirstChild;
        while (child != KE_ENTITY_INVALID)
        {
            var ch   = reg.GetComponentRaw<HierarchyComponent>(child, _world.HierarchyComponentId);
            var next = ch != null ? ch->NextSibling : KE_ENTITY_INVALID;
            DestroyEntityRecursive(child);
            child = next;
        }

        // Unlink from parent's child list
        if (h->Parent != KE_ENTITY_INVALID)
        {
            var ph = reg.GetComponentRaw<HierarchyComponent>(h->Parent, _world.HierarchyComponentId);
            if (ph != null && ph->FirstChild == entity)
                ph->FirstChild = h->NextSibling;

            if (h->PrevSibling != KE_ENTITY_INVALID)
            {
                var ps = reg.GetComponentRaw<HierarchyComponent>(h->PrevSibling, _world.HierarchyComponentId);
                if (ps != null) ps->NextSibling = h->NextSibling;
            }
            if (h->NextSibling != KE_ENTITY_INVALID)
            {
                var ns = reg.GetComponentRaw<HierarchyComponent>(h->NextSibling, _world.HierarchyComponentId);
                if (ns != null) ns->PrevSibling = h->PrevSibling;
            }
        }

        reg.DestroyEntity(entity);
    }

    private static void SetName(ref NameComponent n, string name)
    {
        if (string.IsNullOrEmpty(name)) return;
        var bytes = System.Text.Encoding.UTF8.GetBytes(name);
        fixed (byte* src = bytes)
        fixed (NameComponent* ptr = &n)
        {
            var dst = (byte*)ptr;
            int len = Math.Min(bytes.Length, 63);
            Buffer.MemoryCopy(src, dst, 64, len);
            dst[len] = 0;
        }
    }
}
