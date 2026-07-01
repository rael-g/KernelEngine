using System.Text;
using KernelEngine.Ecs;

namespace KernelEngine.Framework;

/// <summary>
/// Node-aware facade over <see cref="World"/>. Lives in Toolkit (not Framework)
/// because Framework only knows ECS + Scene — it has no concept of <see cref="Node"/>.
/// Game code calls <see cref="AddNode{T}"/> to spawn entities and attach components;
/// every entity is created through the native <see cref="SceneTree"/> so hierarchy
/// and name are wired at the C level.
/// </summary>
public sealed class NodeWorld
{
    private readonly World              _world;
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;
    private readonly uint               _nameCid;

    private readonly List<Node>                  _behaviors = new();
    private readonly List<Label>                 _labels    = new();
    private readonly List<Node>                  _allNodes  = new();
    private readonly Dictionary<string, Node>    _byName    = new(StringComparer.Ordinal);
    private readonly Dictionary<ulong, Node>     _byEntity  = new();

    internal IReadOnlyList<Node>  Behaviors => _behaviors;
    internal IReadOnlyList<Label> Labels    => _labels;

    // The native system context for the tick currently executing. Set by the
    // behavior system around its OnUpdate loop so node create/destroy issued from
    // a behavior defers its structural change to the wave barrier. Zero (default)
    // outside a tick — creation then happens immediately (scene setup, load).
    private nint _systemCtx;

    /// <summary>
    /// Scopes <see cref="AddNode{T}"/>/<see cref="DestroyNode"/> to a running
    /// system's context for the duration of the returned handle, so structural
    /// changes defer to the wave barrier. Restores the prior value on dispose.
    /// </summary>
    internal SystemCtxScope EnterSystem(nint ctx) => new(this, ctx);

    internal readonly ref struct SystemCtxScope
    {
        private readonly NodeWorld _world;
        private readonly nint      _previous;
        public SystemCtxScope(NodeWorld world, nint ctx)
        {
            _world      = world;
            _previous   = world._systemCtx;
            world._systemCtx = ctx;
        }
        public void Dispose() => _world._systemCtx = _previous;
    }

    internal void RegisterBehavior(Node node) => _behaviors.Add(node);
    internal void RegisterLabel(Label label)  => _labels.Add(label);

    // Native "transform" component CID (registered by ke_world_create under "transform").
    // Distinct from the C# "Transform" component (ComponentRegistry, 40 bytes) —
    // this is the kernel 104-byte TransformComponent that includes WorldMatrix.
    // Used in BindNativeEntity to seed the node's _transform before OnBind.
    private readonly uint _nativeTransformCid;
    private readonly uint _hierarchyCid;

    internal NodeWorld(World world, IEcsRegistry ecs, IComponentRegistry components)
    {
        _world      = world;
        _ecs        = ecs;
        _components = components;
        _nameCid            = ecs.RegisterComponent<NameComponent>("name");
        _nativeTransformCid = ecs.RegisterComponent<TransformComponent>("transform");
        _hierarchyCid       = ecs.RegisterComponent<HierarchyComponent>("hierarchy");
    }

    /// <summary>
    /// Registers a node in the world: creates a native entity via the scene tree,
    /// binds the node to it, and lets the subclass materialize its components.
    /// </summary>
    public T AddNode<T>(T node, string name = "", Node? parent = null) where T : Node
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a world.");
        if (parent is not null && parent.NodeWorld != this)
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = _world.SceneTree.CreateNode(name, parent?.Entity ?? 0, _systemCtx);
        node.Name  = name;
        node.BindToNodeWorld(this, entity);
        parent?.AttachChild(node);
        if (!string.IsNullOrEmpty(name)) _byName[name] = node;
        _allNodes.Add(node);
        _byEntity[entity] = node;
        return node;
    }

    /// <summary>
    /// First phase used by the scene loader: assigns entity + name + parent,
    /// but does NOT yet invoke the subclass's OnBind. The loader applies
    /// component data then calls <see cref="CompleteAddNode"/>.
    /// </summary>
    internal void PreAddNode(Node node, string name, Node? parent)
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a world.");
        if (parent is not null && parent.NodeWorld != this)
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = _world.SceneTree.CreateNode(name, parent?.Entity ?? 0, _systemCtx);
        node.Name  = name;
        node.PreBind(this, entity);
        parent?.AttachChild(node);
        if (!string.IsNullOrEmpty(name)) _byName[name] = node;
        _allNodes.Add(node);
        _byEntity[entity] = node;
    }

    internal void CompleteAddNode(Node node) => node.CompleteBind();

    /// <summary>Finds a node by its exact name.</summary>
    public Node? Find(string name) => _byName.TryGetValue(name, out var n) ? n : null;

    /// <summary>Finds a node by name and casts it to <typeparamref name="T"/>.</summary>
    public T? Find<T>(string name) where T : Node
    {
        var node = Find(name);
        if (node is null) return null;
        if (node is not T typed)
            throw new InvalidOperationException(
                $"Node '{name}' is a {node.GetType().Name}, not {typeof(T).Name}.");
        return typed;
    }

    /// <summary>
    /// Removes <paramref name="node"/> from the world, destroys its native entity,
    /// and clears its binding. Idempotent on unbound nodes.
    /// </summary>
    public void DestroyNode(Node node)
    {
        if (!node.IsBound || node.NodeWorld != this) return;
        if (!string.IsNullOrEmpty(node.Name)) _byName.Remove(node.Name);
        var kids = node.Children.ToArray();
        for (int i = 0; i < kids.Length; i++) DestroyNode(kids[i]);

        node.Parent?.DetachChild(node);
        node.OnUnbind();

        if (node.HasBehavior)   _behaviors.Remove(node);
        if (node is Label l)    _labels.Remove(l);
        _allNodes.Remove(node);
        _byEntity.Remove(node.Entity);
        _world.SceneTree.DestroyNode(node.Entity, _systemCtx);
        node.UnbindFromNodeWorld();
    }

    /// <summary>
    /// Destroys every node currently in the world. Used by <see cref="SceneRouter"/>
    /// to flush a scene before loading the next one.
    /// </summary>
    public void Clear()
    {
        var roots = _byName.Values.Where(n => n.Parent is null).ToArray();
        for (int i = 0; i < roots.Length; i++) DestroyNode(roots[i]);
    }

    // ── Native scene loader integration ──────────────────────────────────────

    /// <summary>
    /// Binds a managed Node to an entity that was already created by the native
    /// scene loader. Reads the name from the entity's <c>ke_name_component</c>,
    /// skips native entity creation, and calls OnBind normally.
    /// </summary>
    internal void BindNativeEntity(Node node, ulong entity)
    {
        var name = "";
        var nsp = _ecs.GetComponent<NameComponent>(entity, _nameCid);
        if (!nsp.IsEmpty)
        {
            ReadOnlySpan<byte> bytes = nsp[0].Name;
            var end = bytes.IndexOf((byte)0);
            name = Encoding.UTF8.GetString(end >= 0 ? bytes[..end] : bytes);
        }

        // Seed node._transform from the native "transform" component so that
        // OnBind (called inside BindToNodeWorld) sees the position/scale the
        // scene loader applied before invoking the script factory.
        var tsp = _ecs.GetComponent<TransformComponent>(entity, _nativeTransformCid);
        if (!tsp.IsEmpty)
        {
            ref readonly var kt = ref tsp[0];
            node.SetInitialTransform(new TransformComponent
            {
                Position = kt.Position,
                Rotation = kt.Rotation,
                Scale    = kt.Scale,
            });
        }

        // Wire parent-child via the native HierarchyComponent so Children/Parent
        // reflect the hierarchy declared in the scene file.
        var hsp = _ecs.GetComponent<HierarchyComponent>(entity, _hierarchyCid);
        Node? parent = null;
        if (!hsp.IsEmpty && hsp[0].Parent != 0 && hsp[0].Parent != ulong.MaxValue)
            _byEntity.TryGetValue(hsp[0].Parent, out parent);

        node.Name = name;
        node.BindToNodeWorld(this, entity);
        parent?.AttachChild(node);
        if (!string.IsNullOrEmpty(name)) _byName[name] = node;
        _allNodes.Add(node);
        _byEntity[entity] = node;
    }

    // ── Generic component access ──────────────────────────────────────────────

    /// <summary>
    /// Reads a component by its ECS registration name. Intended for game-specific
    /// components that are not registered in the framework <see cref="IComponentRegistry"/>.
    /// Returns false if the component type is unknown or the entity lacks it.
    /// </summary>
    public bool TryGetComponent<T>(ulong entity, string componentName, out T value) where T : unmanaged
    {
        if (!_ecs.TryLookupComponent(componentName, out var cid))
        {
            value = default;
            return false;
        }
        var sp = _ecs.GetComponent<T>(entity, cid);
        if (sp.IsEmpty) { value = default; return false; }
        value = sp[0];
        return true;
    }

    internal void Set<T>(ulong entity, in T value) where T : unmanaged
    {
        var cid = _components.CidOf<T>();
        if (_systemCtx != 0)
        {
            // Inside a running system. If the entity already carries the component,
            // this is a plain data write (safe mid-wave). If not, adding it is a
            // structural change that must defer to the wave barrier.
            var existing = _ecs.GetComponent<T>(entity, cid);
            if (!existing.IsEmpty) { existing[0] = value; return; }
            if (Runtime.SystemContext.Attach(_systemCtx, entity, cid, in value)) return;
            // No context / defer failed: fall through to the immediate path.
        }
        var sp = _ecs.AddComponent<T>(entity, cid);
        if (!sp.IsEmpty) sp[0] = value;
    }

    internal bool TryGet<T>(ulong entity, out T value) where T : unmanaged
    {
        var sp = _ecs.GetComponent<T>(entity, _components.CidOf<T>());
        if (sp.IsEmpty) { value = default; return false; }
        value = sp[0];
        return true;
    }

    /// <summary>
    /// Calls <see cref="Node.OnReady"/> on every node in reverse insertion order
    /// (children come after parents in a DFS scene load, so reversing gives
    /// children-before-parents ordering). Called by <see cref="SceneRouter"/> after
    /// the scene file is fully loaded.
    /// </summary>
    internal void TriggerReady()
    {
        for (int i = _allNodes.Count - 1; i >= 0; i--)
            _allNodes[i].OnReady();
    }

    /// <summary>
    /// Reads the <c>[entity.properties]</c> block declared in the scene file for
    /// <paramref name="entity"/>. Delegates to <see cref="World.TryGetProperties"/>.
    /// </summary>
    internal bool TryGetProperties(ulong entity, out VariantReader reader)
        => _world.TryGetProperties(entity, out reader);
}
