using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_scene_loader</c> vtable. The C plugin
/// handles TOML parsing, transform application, component-field writes via the
/// world's apply registry, and script-factory dispatch. This shell only owns
/// the unmanaged handle and presents the path-string ABI in a managed-friendly form.
/// </summary>
/// <remarks>
/// Scene grammar (native TOML loader):
/// <code>
/// [scene]
/// name = "Main"
///
/// [[entity]]
/// name   = "Paddle"
/// parent = "World"               # optional; defaults to root
/// type   = "PaddleController"    # dispatched to the registered script factory
/// [entity.transform]
/// position = [0, 1, 0]
/// [entity.components.mesh]
/// primitive = "cube"
/// [entity.properties]
/// Speed = 5.0                    # free-form bag; see ke_scene_properties
/// </code>
/// The loader owns the memory behind every <c>ke_scene_properties</c> component
/// it writes. Dispose this object only after the world has shut down (or after
/// all scene_properties components have been removed).
/// </remarks>
public sealed unsafe class SceneLoader : IDisposable
{
    private ke_scene_loader* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_scene_loader*, void> _destroy;
    private GCHandle _scriptHandle;
    private Func<ulong, string, bool>? _scriptClosure;

    // Pending managed exception from inside ScriptTrampoline, rethrown once
    // the native stack has unwound.
    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void InitPendingException() => s_pendingException = null;
    private static Exception? s_pendingException;

    /// <summary>
    /// Creates a native scene loader bound to <paramref name="world"/>.
    /// </summary>
    /// <param name="world">The world into which entities are loaded.</param>
    /// <param name="projectRoot">
    /// Optional project root for resolving <c>res://</c>-prefixed paths. Pass
    /// <see langword="null"/> to disable res:// resolution.
    /// </param>
    public SceneLoader(World world, string? projectRoot = null)
    {
        ArgumentNullException.ThrowIfNull(world);

        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        ke_scene_loader_handle handle;
        fixed (byte* rootPtr = rootBytes)
        {
            KernelException.ThrowIfFailed(
                KernelEngine.Framework.Native.NativeMethods.scene_loader_create(
                    ((INativeWorld)world).Native,
                    (sbyte*)rootPtr,
                    &handle, null).ToManaged());
        }
        _native = handle.@ref;
        _destroy = handle.destroy;
    }

    /// <summary>
    /// Loads the scene file at <paramref name="path"/> into the world. Blocking.
    /// </summary>
    /// <exception cref="FileNotFoundException">File not found or unparseable.</exception>
    /// <exception cref="KernelException">Any other native failure.</exception>
    public void Load(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentException.ThrowIfNullOrEmpty(path);

        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        s_pendingException = null;
        ke_result result;
        fixed (byte* p = bytes)
            result = _native->load(_native, (sbyte*)p, null);

        if (s_pendingException is { } pending)
        {
            s_pendingException = null;
            throw pending;
        }
        KernelException.ThrowIfFailed(result.ToManaged());
    }

    /// <summary>
    /// Registers the single script factory. When the loader encounters a
    /// <c>type</c> field on an entity it calls <paramref name="factory"/> with
    /// the entity id and the type name. Only one factory is active at a time;
    /// calling again replaces the previous registration.
    /// </summary>
    public void RegisterScriptFactory(Func<ulong, string, bool> factory)
    {
        ArgumentNullException.ThrowIfNull(factory);
        ObjectDisposedException.ThrowIf(_native == null, this);

        if (_scriptHandle.IsAllocated) _scriptHandle.Free();
        _scriptClosure = factory;
        _scriptHandle  = GCHandle.Alloc(factory);
        var ctx        = GCHandle.ToIntPtr(_scriptHandle);

        KernelException.ThrowIfFailed(
            _native->register_script_factory(_native, &ScriptTrampoline, (void*)ctx, null).ToManaged());
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static ke_result ScriptTrampoline(void* ctx, ulong entity, sbyte* typeName)
    {
        try
        {
            var gch = GCHandle.FromIntPtr((IntPtr)ctx);
            if (gch.Target is Func<ulong, string, bool> factory)
            {
                var name = typeName != null ? Marshal.PtrToStringUTF8((IntPtr)typeName) ?? "" : "";
                return factory(entity, name) ? ke_result.KE_OK : ke_result.KE_ERROR;
            }
        }
        catch (Exception ex)
        {
            s_pendingException ??= ex;
        }
        return ke_result.KE_ERROR;
    }

    /// <inheritdoc cref="IDisposable.Dispose"/>
    public void Dispose()
    {
        if (_native is not null)
        {
            if (_destroy != null) _destroy(_native);
            _native = null;
        }
        if (_scriptHandle.IsAllocated) _scriptHandle.Free();
        _scriptClosure = null;
    }
}
