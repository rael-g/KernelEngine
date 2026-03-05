using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// A scene node — represents a spatial object and a unit of behavior.
/// Non-owning wrapper: the <see cref="Scene"/> that created it owns the lifetime.
/// <para>
/// Subclass and override <see cref="OnStart"/>/<see cref="OnUpdate"/> to attach behavior.
/// Pass your subclass instance to <see cref="Scene.CreateNode(Node, string, Allocator)"/>.
/// </para>
/// </summary>
public unsafe class Node
{
    // Static registry: ke_node* address → managed Node, used by native callbacks.
    private static readonly Dictionary<nint, Node> s_registry = [];

    private ke_node* _native;

    internal ke_node* Native => _native;

    /// <summary>Internal constructor used when wrapping an existing native node.</summary>
    internal Node(ke_node* native) => _native = native;

    /// <summary>
    /// Protected parameterless constructor for user subclasses.
    /// The native pointer is set by <see cref="Scene.CreateNode(Node, string, Allocator)"/>.
    /// </summary>
    protected Node() { }

    internal void SetNative(ke_node* native) => _native = native;

    // ── Properties ──────────────────────────────────────────────────────────

    public string Name =>
        Marshal.PtrToStringAnsi((nint)_native->get_name(_native)) ?? string.Empty;

    public Transform LocalTransform
    {
        get
        {
            ke_transform t;
            KernelException.ThrowIfFailed(_native->get_local_transform(_native, &t));
            return Transform.FromNative(t);
        }
        set
        {
            var t = value.ToNative();
            KernelException.ThrowIfFailed(_native->set_local_transform(_native, &t));
        }
    }

    public Matrix4x4 WorldMatrix
    {
        get
        {
            ke_mat4 m;
            KernelException.ThrowIfFailed(_native->get_world_matrix(_native, &m));
            return Unsafe.As<ke_mat4, Matrix4x4>(ref m);
        }
    }

    // ── Hierarchy ────────────────────────────────────────────────────────────

    public Node? Parent
    {
        get
        {
            var p = _native->get_parent(_native);
            return p == null ? null : GetOrWrap(p);
        }
    }

    public Node? FirstChild
    {
        get
        {
            var c = _native->get_first_child(_native);
            return c == null ? null : GetOrWrap(c);
        }
    }

    public Node? NextSibling
    {
        get
        {
            var s = _native->get_next_sibling(_native);
            return s == null ? null : GetOrWrap(s);
        }
    }

    public void AddChild(Node child) =>
        KernelException.ThrowIfFailed(_native->add_child(_native, child._native));

    public void RemoveChild(Node child) =>
        KernelException.ThrowIfFailed(_native->remove_child(_native, child._native));

    // ── ECS Entity Link ──────────────────────────────────────────────────────

    public ulong Entity => _native->get_entity(_native);

    // ── Script Overrides ─────────────────────────────────────────────────────

    /// <summary>Called once when the world starts this node.</summary>
    protected virtual void OnStart() { }

    /// <summary>Called every frame by the world update loop.</summary>
    protected virtual void OnUpdate(float deltaTime) { }

    // ── Internal ─────────────────────────────────────────────────────────────

    private bool _started;

    internal void InvokeLifecycle(float dt)
    {
        if (!_started)
        {
            _started = true;
            OnStart();
        }
        OnUpdate(dt);
    }

    internal static IEnumerable<Node> AllScripted => s_registry.Values;

    internal void Register() => s_registry[(nint)_native] = this;

    internal static void Unregister(ke_node* native) =>
        s_registry.Remove((nint)native);

    internal static Node GetOrWrap(ke_node* native)
    {
        if (s_registry.TryGetValue((nint)native, out var existing))
            return existing;
        return new Node(native);
    }

    // ── Unmanaged Script Callbacks ────────────────────────────────────────────

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static ke_result NativeOnStart(ke_node* self)
    {
        if (s_registry.TryGetValue((nint)self, out var node))
            node.OnStart();
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static ke_result NativeOnUpdate(ke_node* self, float dt)
    {
        if (s_registry.TryGetValue((nint)self, out var node))
            node.OnUpdate(dt);
        return ke_result.KE_OK;
    }
}
