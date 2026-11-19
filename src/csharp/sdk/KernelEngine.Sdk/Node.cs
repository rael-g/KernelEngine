using KernelEngine.Ecs;
using KernelEngine.Framework.Nodes.Native;

namespace KernelEngine.Framework.Nodes;

/// <summary>
/// A node type as C#: one instance stands for every node of the type, and while a behaviour runs it
/// is bound to the node the behaviour is visiting, so its properties are that node's memory and its
/// methods act on that node. Outside a behaviour its properties are the value a node is born with: the
/// constructor runs once, when the instance is made for registration, and what it writes is the type's
/// initial value; nothing runs when a node is born.
/// </summary>
public abstract class Node
{
    INodeCtx? _ctx;

    /// <summary>The world the type is registered in; set by <see cref="NodeWorld.Register"/>.</summary>
    public NodeWorld World { get; internal set; } = null!;

    Microsoft.Extensions.Logging.ILogger? _log;

    /// <summary>The logger of the type, under the type's name.</summary>
    protected Microsoft.Extensions.Logging.ILogger Log => _log ??= World.Logging.CreateLogger(GetType().FullName ?? GetType().Name);

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

    /// <summary>
    /// Records a node under the current node of the engine node type named after <typeparamref name="T"/>
    /// (a sound for <c>SoundComponent</c>), born holding <paramref name="component"/>.
    /// </summary>
    protected Entity Spawn<T>(string name, T component) where T : unmanaged, KernelEngine.Interop.IComponentName =>
        Ctx.Spawn(World.Type(T.RegisteredName), name, Self, [NodeComponent.Of(World.Component(T.RegisteredName), component)]);

    /// <summary>The child of the current node named <paramref name="name"/>; the default entity when it has none.</summary>
    protected Entity Child(string name) => Ctx.Child(Self, name);

    /// <summary>
    /// Whether the action named by <paramref name="action"/> was pressed this tick. The action is resolved
    /// into <paramref name="action"/> on its first read when it is a variable (a field or a node property);
    /// a copy is resolved again on every read.
    /// </summary>
    protected bool Pressed(in ActionRef action) => Ctx.Pressed(ref System.Runtime.CompilerServices.Unsafe.AsRef(in action));

    /// <summary>The value of the axis action named by <paramref name="action"/>, resolved as <see cref="Pressed(in ActionRef)"/> resolves it.</summary>
    protected float Axis(in ActionRef action) => Ctx.Axis(ref System.Runtime.CompilerServices.Unsafe.AsRef(in action));

    /// <summary>Whether the button action named <paramref name="action"/> was pressed this tick.</summary>
    protected bool Pressed(string action) => Ctx.PressedNamed(action);

    /// <summary>The value of the axis action named <paramref name="action"/>.</summary>
    protected float Axis(string action) => Ctx.AxisNamed(action);

    /// <summary>Raises <paramref name="value"/> as an event of its type.</summary>
    protected void Raise<T>(T value) where T : unmanaged => Ctx.Raise(World.EventId<T>(), value);

    /// <summary>Records a node of the type named <paramref name="type"/> under the current node.</summary>
    protected Entity Spawn(string type, string name, params ReadOnlySpan<NodeComponent> components) =>
        Ctx.Spawn(World.Type(type), name, Self, components);

    /// <summary>Records the destruction of <paramref name="node"/> and its descendants.</summary>
    protected void Destroy(Entity node) => Ctx.Destroy(node);

    /// <summary>Points the nearest scene slot above the current node at the scene file <paramref name="path"/>.</summary>
    /// <exception cref="Exception">No scene slot holds the node.</exception>
    protected void ChangeScene(string path) => Ctx.ChangeScene(path);

    /// <summary>Asks the runtime for the program to end.</summary>
    protected void Exit() => Ctx.Exit();
}
