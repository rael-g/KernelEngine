using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node backed by an ECS entity. Represents a spatial object with optional behavior.
/// <para>
/// Subclass and override <see cref="OnStart"/>/<see cref="OnUpdate"/> to attach behavior.
/// The entity is created by the world; transform and hierarchy live in ECS components.
/// </para>
/// </summary>
public unsafe class Node
{
    // Entity → managed Node, used by the [UnmanagedCallersOnly] script callbacks.
    private static readonly Dictionary<ulong, Node> s_registry = [];

    private ulong _entity;
    private World? _world;
    private string _name = "";

    /// <summary>Parameterless constructor for user subclasses.</summary>
    protected Node() { }

    /// <summary>Internal constructor for wrapping an existing entity (e.g. root).</summary>
    internal Node(ulong entity, World world, string name)
    {
        _entity = entity;
        _world = world;
        _name = name;
        s_registry[_entity] = this;
    }

    /// <summary>Called by <see cref="Scene.AddNode{T}"/> to bind this instance to an entity.</summary>
    internal void Initialize(ulong entity, World world, string name)
    {
        _entity = entity;
        _world = world;
        _name = name;
        s_registry[_entity] = this;
    }

    /// <summary>
    /// Adds a <see cref="ScriptComponent"/> to the ECS entity so the C ScriptSystem
    /// will call <see cref="OnStart"/> and <see cref="OnUpdate"/> each frame.
    /// </summary>
    internal void RegisterScript()
    {
        if (_world == null) return;
        s_registry[_entity] = this;

        var script = _world.Registry.AddComponent<ScriptComponent>(_entity, _world.ScriptComponentId);
        script[0] = new ScriptComponent
        {
            Started = 0,
            OnStart = &NativeOnStart,
            OnUpdate = &NativeOnUpdate,
        };
    }

    // ── Identity ──────────────────────────────────────────────────────────────

    /// <summary>The ECS entity ID. Immutable after node creation.</summary>
    public ulong Entity => _entity;

    /// <summary>The name given at node creation.</summary>
    public string Name => _name;

    // ── Transform ─────────────────────────────────────────────────────────────

    /// <summary>Local spatial transform (position, rotation, scale).</summary>
    public Transform LocalTransform
    {
        get
        {
            var c = TransformPtr;
            if (c == null) return Transform.Identity;
            return new Transform { Position = c->Position, Rotation = c->Rotation, Scale = c->Scale };
        }
        set
        {
            var c = TransformPtr;
            if (c == null) return;
            c->Position = value.Position;
            c->Rotation = value.Rotation;
            c->Scale = value.Scale;
        }
    }

    /// <summary>World-space matrix, computed each frame by the TransformSystem.</summary>
    public Matrix4x4 WorldMatrix
    {
        get
        {
            var c = TransformPtr;
            return c != null ? c->WorldMatrix : Matrix4x4.Identity;
        }
    }

    private TransformComponent* TransformPtr
    {
        get
        {
            if (_world == null) return null;
            return _world.Registry.GetComponentRaw<TransformComponent>(_entity, _world.TransformComponentId);
        }
    }

    // ── Hierarchy ─────────────────────────────────────────────────────────────

    /// <summary>Parent node, or <c>null</c> if this is the root.</summary>
    public Node? Parent
    {
        get
        {
            var h = HierarchyPtr;
            return h != null && h->Parent != 0 ? s_registry.GetValueOrDefault(h->Parent) : null;
        }
    }

    /// <summary>First child, or <c>null</c> if none.</summary>
    public Node? FirstChild
    {
        get
        {
            var h = HierarchyPtr;
            return h != null && h->FirstChild != 0 ? s_registry.GetValueOrDefault(h->FirstChild) : null;
        }
    }

    /// <summary>Next sibling, or <c>null</c> if this is the last child.</summary>
    public Node? NextSibling
    {
        get
        {
            var h = HierarchyPtr;
            return h != null && h->NextSibling != 0 ? s_registry.GetValueOrDefault(h->NextSibling) : null;
        }
    }

    private HierarchyComponent* HierarchyPtr
    {
        get
        {
            if (_world == null) return null;
            return _world.Registry.GetComponentRaw<HierarchyComponent>(_entity, _world.HierarchyComponentId);
        }
    }

    // ── ECS helpers for subclasses ────────────────────────────────────────────

    /// <summary>Adds a component to this node's entity and returns a reference to it.</summary>
    protected ref T AddComponent<T>(uint componentId) where T : unmanaged =>
        ref *_world!.Registry.AddComponentRaw<T>(_entity, componentId);

    /// <summary>Returns a pointer to the component, or <c>null</c> if not present.</summary>
    protected T* GetComponent<T>(uint componentId) where T : unmanaged =>
        _world!.Registry.GetComponentRaw<T>(_entity, componentId);

    /// <summary>Removes a component from this node's entity.</summary>
    protected void RemoveComponent(uint componentId) =>
        _world!.Registry.RemoveComponent(_entity, componentId);

    // ── Script overrides ──────────────────────────────────────────────────────

    /// <summary>Called once before the first <see cref="OnUpdate"/> call.</summary>
    protected virtual void OnStart() { }

    /// <summary>Called every frame.</summary>
    protected virtual void OnUpdate(float deltaTime) { }

    // ── Internal registry ─────────────────────────────────────────────────────

    internal static Node? FromEntity(ulong entity) => s_registry.GetValueOrDefault(entity);

    internal static void Unregister(ulong entity) => s_registry.Remove(entity);

    internal static void ClearRegistry() => s_registry.Clear();

    // ── Unmanaged callbacks (called by the C ScriptSystem) ────────────────────

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static KernelResult NativeOnStart(ulong entity)
    {
        if (s_registry.TryGetValue(entity, out var node))
            node.OnStart();
        return KernelResult.Ok;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static KernelResult NativeOnUpdate(ulong entity, float dt)
    {
        if (s_registry.TryGetValue(entity, out var node))
            node.OnUpdate(dt);
        return KernelResult.Ok;
    }
}
