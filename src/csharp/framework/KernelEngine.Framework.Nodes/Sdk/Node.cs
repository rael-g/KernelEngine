using KernelEngine.Ecs;
using KernelEngine.Framework.Nodes.Native;

namespace KernelEngine.Framework.Nodes;

/// <summary>
/// A node type as C#: one instance stands for every node of the type, and while a behaviour runs it
/// is bound to the node the behaviour is visiting, so its properties are that node's memory and its
/// methods act on that node. Outside a behaviour its properties are the value a node is born with.
/// </summary>
public abstract class Node
{
    INodeCtx? _ctx;

    /// <summary>The world the type is registered in; set by <see cref="NodeWorld.Register"/>.</summary>
    public NodeWorld World { get; internal set; } = null!;

    /// <summary>Whether a behaviour is running, so the properties read a node rather than the birth value.</summary>
    protected bool Bound => _ctx is not null;

    /// <summary>The context of the running behaviour.</summary>
    /// <exception cref="InvalidOperationException">No behaviour is running.</exception>
    protected INodeCtx Ctx => _ctx ?? throw new InvalidOperationException("a node is reached only while one of its behaviours runs");

    /// <summary>The node the running behaviour is visiting.</summary>
    public Entity Self => Ctx.Self;

    /// <summary>Seconds since the previous tick, or the fixed step in a fixed update.</summary>
    protected float Dt => Ctx.Dt;

    /// <summary>The components every node of the type carries beside its fields, and how each is born.</summary>
    protected internal virtual IEnumerable<NodeWith> With => [];

    /// <summary>Registers the type into <paramref name="world"/>; written by the node type generator.</summary>
    protected internal abstract ComponentId RegisterInto(NodeWorld world);

    /// <summary>Runs <paramref name="visit"/> once per node of the type, bound to it.</summary>
    protected void Visit(INodeCtx ctx, Action visit)
    {
        _ctx = ctx;
        try
        {
            while (ctx.Next()) visit();
        }
        finally
        {
            _ctx = null;
        }
    }

    /// <summary>The current node's component registered under <paramref name="name"/>.</summary>
    protected ref T Component<T>(string name) where T : unmanaged => ref Ctx.Get<T>(World.Component(name));

    /// <summary><paramref name="node"/>'s component registered under <paramref name="name"/>.</summary>
    protected ref T Component<T>(Entity node, string name) where T : unmanaged => ref Ctx.Component<T>(node, World.Component(name));

    /// <summary><paramref name="node"/>'s component of type <typeparamref name="T"/>.</summary>
    protected ref T Get<T>(Entity node) where T : unmanaged, KernelEngine.Interop.IComponentName =>
        ref Ctx.Component<T>(node, World.Component(T.RegisteredName));

    /// <summary>The component of type <typeparamref name="T"/> of the current node's child named <paramref name="name"/>.</summary>
    /// <exception cref="InvalidOperationException">The node has no child of that name.</exception>
    protected ref T Child<T>(string name) where T : unmanaged, KernelEngine.Interop.IComponentName
    {
        var child = Child(name);
        if (child == default) throw new InvalidOperationException($"the node has no child named {name}");
        return ref Get<T>(child);
    }

    /// <summary>Records a node of the type named <paramref name="type"/> under the current node, born holding <paramref name="component"/>.</summary>
    protected Entity Spawn<T>(string type, string name, T component) where T : unmanaged, KernelEngine.Interop.IComponentName =>
        Ctx.Spawn(World.Type(type), name, Self, [NodeComponent.Of(World.Component(T.RegisteredName), component)]);

    /// <summary>The child of the current node named <paramref name="name"/>; the default entity when it has none.</summary>
    protected Entity Child(string name) => Ctx.Child(Self, name);

    /// <summary>Whether the action named by <paramref name="action"/> was pressed this tick.</summary>
    protected bool Pressed(ref ActionRef action) => Ctx.Pressed(ref action);

    /// <summary>The value of the axis action named by <paramref name="action"/>.</summary>
    protected float Axis(ref ActionRef action) => Ctx.Axis(ref action);

    /// <summary>Raises <paramref name="value"/> as an event of its type.</summary>
    protected void Raise<T>(T value) where T : unmanaged => Ctx.Raise(World.EventId<T>(), value);

    /// <summary>Records a node of the type named <paramref name="type"/> under the current node.</summary>
    protected Entity Spawn(string type, string name, params ReadOnlySpan<NodeComponent> components) =>
        Ctx.Spawn(World.Type(type), name, Self, components);

    /// <summary>Records the destruction of <paramref name="node"/> and its descendants.</summary>
    protected void Destroy(Entity node) => Ctx.Destroy(node);

    /// <summary>Points the nearest scene slot above the current node at the scene file <paramref name="path"/>.</summary>
    /// <exception cref="InvalidOperationException">No scene slot holds the node.</exception>
    protected void ChangeScene(string path)
    {
        var slot = World.Component("scene_slot");
        var holder = Ctx.Ancestor(Self, slot);
        if (holder == default) throw new InvalidOperationException("no scene slot holds this node");
        Ctx.Component<SceneSlotComponent>(holder, slot).PathText = path;
    }

    /// <summary>Asks the runtime for the program to end.</summary>
    protected void Exit() => Ctx.Exit();
}
