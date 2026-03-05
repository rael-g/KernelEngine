using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// Manages a hierarchy of nodes.
/// Non-owning view: the <see cref="World"/> that created it controls lifetime.
/// </summary>
public sealed unsafe class Scene
{
    private readonly ke_scene* _native;

    internal Scene(ke_scene* native) => _native = native;

    /// <summary>The implicit root node of this scene.</summary>
    public Node Root => Node.GetOrWrap(_native->get_root(_native));

    // ── Low-level factory ─────────────────────────────────────────────────────

    /// <summary>
    /// Creates a plain (non-scripted) named node without inserting it into the hierarchy.
    /// Use <see cref="AddNode(string,Node?)"/> for the common case.
    /// </summary>
    public Node CreateNode(string name)
    {
        var namePtr = Marshal.StringToHGlobalAnsi(name);
        try
        {
            var desc = new ke_node_descriptor { name = (sbyte*)namePtr };
            ke_node* native;
            KernelException.ThrowIfFailed(_native->create_node(_native, &desc, &native));
            return new Node(native);
        }
        finally { Marshal.FreeHGlobal(namePtr); }
    }

    /// <summary>
    /// Creates a scripted node without inserting it into the hierarchy.
    /// Use <see cref="AddNode{T}(T,string,Node?)"/> for the common case.
    /// </summary>
    public T CreateNode<T>(T node, string name) where T : Node
    {
        var namePtr = Marshal.StringToHGlobalAnsi(name);
        try
        {
            var desc = new ke_node_descriptor
            {
                name = (sbyte*)namePtr,
                on_start = &Node.NativeOnStart,
                on_update = &Node.NativeOnUpdate,
            };
            ke_node* native;
            KernelException.ThrowIfFailed(_native->create_node(_native, &desc, &native));
            node.SetNative(native);
            node.Register();
            return node;
        }
        finally { Marshal.FreeHGlobal(namePtr); }
    }

    // ── High-level add ────────────────────────────────────────────────────────

    /// <summary>
    /// Creates a plain node and adds it as a child of <paramref name="parent"/>
    /// (defaults to <see cref="Root"/>).
    /// </summary>
    public Node AddNode(string name, Node? parent = null)
    {
        var node = CreateNode(name);
        (parent ?? Root).AddChild(node);
        return node;
    }

    /// <summary>
    /// Creates a scripted node and adds it as a child of <paramref name="parent"/>
    /// (defaults to <see cref="Root"/>).
    /// </summary>
    public T AddNode<T>(T node, string name, Node? parent = null) where T : Node
    {
        CreateNode(node, name);
        (parent ?? Root).AddChild(node);
        return node;
    }

    // ── Destruction ───────────────────────────────────────────────────────────

    /// <summary>
    /// Destroys a node and removes it from the scripting registry.
    /// Do not use <paramref name="node"/> after this call.
    /// </summary>
    public void DestroyNode(Node node)
    {
        Node.Unregister(node.Native);
        KernelException.ThrowIfFailed(_native->destroy_node(_native, node.Native));
    }
}
