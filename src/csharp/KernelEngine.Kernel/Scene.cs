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

    /// <summary>
    /// Creates a plain (non-scripted) named node under this scene.
    /// </summary>
    public Node CreateNode(string name, Allocator allocator)
    {
        var namePtr = Marshal.StringToHGlobalAnsi(name);
        try
        {
            var desc = new ke_node_descriptor
            {
                name = (sbyte*)namePtr,
                allocator = (ke_node_descriptor.ke_allocator*)allocator.Native,
            };
            ke_node* native;
            KernelException.ThrowIfFailed(_native->create_node(_native, &desc, &native));
            return new Node(native);
        }
        finally
        {
            Marshal.FreeHGlobal(namePtr);
        }
    }

    /// <summary>
    /// Creates a scripted node and wires up the managed <see cref="Node"/> instance's
    /// <c>OnStart</c>/<c>OnUpdate</c> overrides to native callbacks.
    /// </summary>
    /// <param name="node">
    /// A pre-constructed <see cref="Node"/> subclass instance.
    /// Its native pointer will be set by this call.
    /// </param>
    /// <example>
    /// <code>
    /// var player = scene.CreateNode(new PlayerNode(), "Player", allocator);
    /// </code>
    /// </example>
    public T CreateNode<T>(T node, string name, Allocator allocator) where T : Node
    {
        var namePtr = Marshal.StringToHGlobalAnsi(name);
        try
        {
            var desc = new ke_node_descriptor
            {
                name = (sbyte*)namePtr,
                allocator = (ke_node_descriptor.ke_allocator*)allocator.Native,
                on_start = &Node.NativeOnStart,
                on_update = &Node.NativeOnUpdate,
            };
            ke_node* native;
            KernelException.ThrowIfFailed(_native->create_node(_native, &desc, &native));
            node.SetNative(native);
            node.Register();
            return node;
        }
        finally
        {
            Marshal.FreeHGlobal(namePtr);
        }
    }

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
