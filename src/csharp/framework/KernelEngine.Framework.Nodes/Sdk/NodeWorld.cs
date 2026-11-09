using System.Runtime.CompilerServices;

using KernelEngine.Ecs;

namespace KernelEngine.Framework.Nodes;

/// <summary>
/// The node types of one world as C# names them: the ids of the components and event types a node
/// reaches by name or by type, looked up once and kept.
/// </summary>
public sealed class NodeWorld(INodeTypes types)
{
    readonly Dictionary<string, ComponentId> _components = [];
    readonly Dictionary<Type, ComponentId> _events = [];

    /// <summary>The node types this world registers into.</summary>
    public INodeTypes Types { get; } = types;

    /// <summary>Registers the event type <typeparamref name="T"/>, named after it.</summary>
    /// <returns>The event's id.</returns>
    public ComponentId RegisterEvent<T>() where T : unmanaged
    {
        var id = Types.RegisterEvent(typeof(T).FullName!, (nuint)Unsafe.SizeOf<T>(), AlignOf<T>(), []);
        _events[typeof(T)] = id;
        return id;
    }

    struct Probe<T> where T : unmanaged
    {
        public byte Head;
        public T Value;
    }

    static nuint AlignOf<T>() where T : unmanaged
    {
        var probe = new Probe<T> { Head = 1 };
        return (nuint)Unsafe.ByteOffset(ref probe.Head, ref Unsafe.As<T, byte>(ref probe.Value));
    }

    /// <summary>The id of the event type <typeparamref name="T"/>.</summary>
    /// <exception cref="InvalidOperationException"><typeparamref name="T"/> was never registered.</exception>
    public ComponentId EventId<T>() where T : unmanaged =>
        _events.TryGetValue(typeof(T), out var id) ? id : throw new InvalidOperationException($"the event {typeof(T).Name} was never registered");

    /// <summary>The id of the component registered under <paramref name="name"/>.</summary>
    public ComponentId Component(string name)
    {
        if (!_components.TryGetValue(name, out var id)) _components[name] = id = Types.FindComponent(name);
        return id;
    }

    /// <summary>The id of the node type registered under <paramref name="name"/>.</summary>
    public ComponentId Type(string name) => Types.FindType(name);

    /// <summary>Registers the node type <paramref name="node"/> is an instance of, which then stands for every node of it.</summary>
    /// <returns>The type's id.</returns>
    public ComponentId Register(Node node)
    {
        node.World = this;
        return node.RegisterInto(this);
    }
}
