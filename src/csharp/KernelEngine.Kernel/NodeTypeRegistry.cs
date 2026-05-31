using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed bridge over <c>ke_node_type_registry</c>.
/// <para>
/// Each language binding registers its node types here by string name. The kernel vtable
/// is wired so any future caller — including non-.NET runtimes — can create nodes and set
/// properties through the C ABI. The C# trampoline bodies delegate to the existing reflection
/// machinery (same as <c>SceneLoader</c> today), satisfying the round-trip pattern of Tier S:
/// the C# Framework IS the implementation behind the kernel contract.
/// </para>
/// </summary>
public sealed unsafe class NodeTypeRegistry : IDisposable
{
    // ── Per-type entry (stored in a GCHandle so the trampoline can recover it from ctx) ──

    private sealed class TypeEntry
    {
        public required Type   NodeType { get; init; }
        public IServiceProvider? Services { get; init; }
    }

    // ── Static tables (shared across all instances — trampolines are static) ──────────────

    // entity → node object created by the create trampoline.
    // Typed as object so KernelEngine.Kernel has no dependency on KernelEngine.Framework's Node.
    // Callers (e.g. SceneLoader in S3) cast to their concrete node type.
    internal static readonly Dictionary<ulong, object> PendingNodes = [];

    // Prevents GCHandles from being collected while the registry is alive.
    private readonly List<GCHandle> _handles = [];
    // Unmanaged name strings (allocated with Marshal, freed on Dispose).
    private readonly List<nint> _nameStrings = [];

    private ke_node_type_registry* _native;

    // ── Construction ─────────────────────────────────────────────────────────────────────

    /// <summary>Creates a registry backed by the given allocator.</summary>
    public NodeTypeRegistry(Allocator allocator)
    {
        ke_node_type_registry* reg;
        KernelException.ThrowIfFailed(
            NativeMethods.node_type_registry_create(allocator.Native, &reg).ToManaged());
        _native = reg;
    }

    // ── Registration ──────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Registers a Node subclass under <paramref name="name"/>. The kernel vtable slots
    /// <c>create</c> and <c>set_property</c> are wired to C# trampolines that delegate to
    /// the existing reflection-based instantiation and property hydration.
    /// </summary>
    public void Register(string name, Type nodeType, IServiceProvider? services = null)
    {
        ArgumentNullException.ThrowIfNull(name);
        ArgumentNullException.ThrowIfNull(nodeType);

        // Note: we can't check IsAssignableFrom(Node) here since Node lives in KernelEngine.Framework.
        // The caller is responsible for passing a Node subclass.

        var entry = new TypeEntry { NodeType = nodeType, Services = services };
        var handle = GCHandle.Alloc(entry);
        _handles.Add(handle);

        // Allocate an unmanaged copy of the name string (registry stores the pointer).
        var namePtr = Marshal.StringToCoTaskMemUTF8(name);
        _nameStrings.Add(namePtr);

        var descriptor = new ke_node_type
        {
            name         = (sbyte*)namePtr,
            ctx          = (void*)GCHandle.ToIntPtr(handle),
            create       = &NativeCreate,
            set_property = &NativeSetProperty,
        };

        KernelException.ThrowIfFailed(
            _native->register_type(_native, &descriptor).ToManaged());
    }

    /// <summary>Typed convenience over <see cref="Register(string, Type, IServiceProvider?)"/>.</summary>
    public void Register<T>(string name, IServiceProvider? services = null)
        => Register(name, typeof(T), services);

    // ── Native lookup (pass-through to kernel) ────────────────────────────────────────────

    /// <summary>
    /// Resolves a type descriptor by name. Returns <c>false</c> when not found.
    /// The returned pointer is valid for the lifetime of this registry.
    /// </summary>
    public bool TryLookup(string name, out ke_node_type* outType)
    {
        ke_node_type* found;
        fixed (byte* nameBytes = System.Text.Encoding.UTF8.GetBytes(name + "\0"))
        {
            var res = _native->lookup(_native, (sbyte*)nameBytes, &found);
            if (res == ke_result.KE_OK)
            {
                outType = found;
                return true;
            }
        }
        outType = null;
        return false;
    }

    // ── Trampolines ───────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Called by the C ScriptSystem (or future Lua binding) when a new node entity needs a
    /// managed Node object. Creates the instance via reflection / DI, stores it keyed by
    /// entity in <see cref="PendingNodes"/> for the caller (e.g. S3 SceneLoader) to retrieve.
    /// </summary>
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeCreate(void* ctx, ulong entity, sbyte* name)
    {
        try
        {
            var entry = (TypeEntry)GCHandle.FromIntPtr((nint)ctx).Target!;
            var instance = entry.Services is not null
                ? Microsoft.Extensions.DependencyInjection.ActivatorUtilities.CreateInstance(entry.Services, entry.NodeType)
                : Activator.CreateInstance(entry.NodeType)!;
            PendingNodes[entity] = instance;
            return ke_result.KE_OK;
        }
        catch
        {
            return ke_result.KE_ERROR;
        }
    }

    /// <summary>
    /// Called by the SceneLoader (S3) or a test to set a single property on the node
    /// identified by <paramref name="entity"/>. Converts <paramref name="value"/> from
    /// <c>ke_variant</c> to the property's CLR type via reflection.
    /// </summary>
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeSetProperty(void* ctx, ulong entity, sbyte* key, ke_variant value)
    {
        try
        {
            if (!PendingNodes.TryGetValue(entity, out var node)) return ke_result.KE_ERROR_NOT_FOUND;

            var keyStr = Marshal.PtrToStringUTF8((nint)key);
            if (keyStr is null) return ke_result.KE_ERROR_INVALID_ARGUMENT;

            var prop = node!.GetType().GetProperty(
                keyStr, BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase);
            if (prop is null || !prop.CanWrite) return ke_result.KE_OK; // silently skip unknown props

            var converted = VariantToObject(value, prop.PropertyType);
            prop.SetValue(node, converted);
            return ke_result.KE_OK;
        }
        catch
        {
            return ke_result.KE_ERROR;
        }
    }

    // ── ke_variant → CLR conversion ───────────────────────────────────────────────────────

    private static object? VariantToObject(ke_variant v, Type targetType)
    {
        var underlying = Nullable.GetUnderlyingType(targetType) ?? targetType;

        return v.type switch
        {
            ke_variant_type.KE_VARIANT_NULL   => null,
            ke_variant_type.KE_VARIANT_BOOL   => System.Convert.ChangeType(v.b, underlying),
            ke_variant_type.KE_VARIANT_INT    => System.Convert.ChangeType(v.i, underlying),
            ke_variant_type.KE_VARIANT_FLOAT  => System.Convert.ChangeType(v.f, underlying),
            ke_variant_type.KE_VARIANT_STRING => ConvertString(v.s, underlying),
            ke_variant_type.KE_VARIANT_VEC2   => ConvertVec2(v.v2, underlying),
            ke_variant_type.KE_VARIANT_VEC3   => ConvertVec3(v.v3, underlying),
            ke_variant_type.KE_VARIANT_VEC4   => ConvertVec4(v.v4, underlying),
            ke_variant_type.KE_VARIANT_QUAT   => ConvertQuat(v.q, underlying),
            _                                 => null,
        };
    }

    private static object? ConvertString(sbyte* s, Type target)
    {
        var str = Marshal.PtrToStringUTF8((nint)s);
        if (target == typeof(string)) return str;
        if (target.IsEnum && str != null) return Enum.Parse(target, str, ignoreCase: true);
        return str is null ? null : System.Convert.ChangeType(str, target);
    }

    private static object ConvertVec2(ke_vec2 v, Type target)
    {
        if (target == typeof(System.Numerics.Vector2))
            return new System.Numerics.Vector2(v.x, v.y);
        throw new InvalidCastException($"Cannot convert KE_VARIANT_VEC2 to {target.Name}");
    }

    private static object ConvertVec3(ke_vec3 v, Type target)
    {
        if (target == typeof(System.Numerics.Vector3))
            return new System.Numerics.Vector3(v.x, v.y, v.z);
        throw new InvalidCastException($"Cannot convert KE_VARIANT_VEC3 to {target.Name}");
    }

    private static object ConvertVec4(ke_vec4 v, Type target)
    {
        if (target == typeof(System.Numerics.Vector4))
            return new System.Numerics.Vector4(v.x, v.y, v.z, v.w);
        throw new InvalidCastException($"Cannot convert KE_VARIANT_VEC4 to {target.Name}");
    }

    private static object ConvertQuat(ke_quat q, Type target)
    {
        if (target == typeof(System.Numerics.Quaternion))
            return new System.Numerics.Quaternion(q.x, q.y, q.z, q.w);
        throw new InvalidCastException($"Cannot convert KE_VARIANT_QUAT to {target.Name}");
    }

    // ── Dispose ───────────────────────────────────────────────────────────────────────────

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
        foreach (var h in _handles) h.Free();
        _handles.Clear();
        foreach (var p in _nameStrings) Marshal.FreeCoTaskMem(p);
        _nameStrings.Clear();
    }
}
