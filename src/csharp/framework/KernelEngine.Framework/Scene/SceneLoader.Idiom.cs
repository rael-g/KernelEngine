using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Common.Native;

namespace KernelEngine.Framework;

/// <summary>
/// The parts of <see cref="SceneLoader"/> that are not a direct image of the C ABI:
/// the constructor's factory call (<c>ke_scene_loader_create</c> lives outside this
/// domain's own headers, alongside the world/asset-resolver factories), <see cref="Load"/>'s
/// pending-exception rethrow (a script factory can throw mid-load; the trampoline
/// catches it and this rethrows once the native stack has unwound — no ABI counterpart),
/// and <see cref="RegisterScriptFactory"/>'s GCHandle/trampoline bridging for the bare
/// <c>[raw_callback]</c> function pointer. Everything that mirrors the vtable 1:1 is
/// generated in <c>Generated/SceneLoader.g.cs</c>.
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
/// [entity.mesh]
/// mesh = "cube"                  # every value a scene authors is a component field
/// </code>
/// </remarks>
public unsafe partial class SceneLoader
{
    private GCHandle _scriptHandle;
    private Func<ulong, string, bool>? _scriptClosure;

    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void InitPendingException() => s_pendingException = null;
    private static Exception? s_pendingException;

    /// <summary>
    /// Holds an exception raised inside a callback the native loader invoked, to be
    /// rethrown by <c>Load</c> once the native stack has unwound.
    /// </summary>
    /// <remarks>
    /// Letting it propagate through native frames is undefined behaviour, and swallowing
    /// it turns a scene the engine could not honour into a game that starts anyway.
    /// </remarks>
    internal static void ParkException(Exception ex) => s_pendingException ??= ex;

    /// <summary>
    /// Creates a native scene loader bound to <paramref name="world"/>.
    /// </summary>
    /// <param name="world">The world into which entities are loaded.</param>
    /// <param name="projectRoot">
    /// Optional project root for resolving <c>res://</c>-prefixed paths. Pass
    /// <see langword="null"/> to disable res:// resolution.
    /// </param>
    public SceneLoader(World world, string? projectRoot = null) : this(Create(world, projectRoot))
    {
    }

    private static ke_scene_loader_handle Create(World world, string? projectRoot)
    {
        ArgumentNullException.ThrowIfNull(world);

        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        fixed (byte* rootPtr = rootBytes)
        {
            ke_error* err = null;
            var handle = KernelEngine.Framework.Native.NativeMethods.scene_loader_create(
                ((INativeWorld)world).Native, (sbyte*)rootPtr, &err);
            if (handle.@ref == null) throw KernelError.FromNative(err, "scene_loader_create");
            return handle;
        }
    }

    /// <summary>
    /// Loads the scene file at <paramref name="path"/> into the world. Blocking.
    /// </summary>
    /// <exception cref="FileNotFoundException">File not found or unparseable.</exception>
    /// <exception cref="KernelError">Any other native failure.</exception>
    public void Load(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        var native = ((INativeSceneLoader)this).Native;

        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        s_pendingException = null;
        ke_error* err = null;
        bool result;
        fixed (byte* p = bytes)
            result = native->load(native, (sbyte*)p, &err);

        if (s_pendingException is { } pending)
        {
            s_pendingException = null;
            throw pending;
        }
        KernelError.ThrowIfFailed(result, err, "load");
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
        var native = ((INativeSceneLoader)this).Native;

        if (_scriptHandle.IsAllocated) _scriptHandle.Free();
        _scriptClosure = factory;
        _scriptHandle  = GCHandle.Alloc(factory);
        var ctx        = GCHandle.ToIntPtr(_scriptHandle);

        ke_error* err = null;
        KernelError.ThrowIfFailed(
            native->register_script_factory(native, &ScriptTrampoline, (void*)ctx, &err), err, "register_script_factory");
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static bool ScriptTrampoline(void* ctx, ulong entity, sbyte* typeName, ke_error** out_error)
    {
        try
        {
            var gch = GCHandle.FromIntPtr((IntPtr)ctx);
            if (gch.Target is Func<ulong, string, bool> factory)
            {
                var name = typeName != null ? Marshal.PtrToStringUTF8((IntPtr)typeName) ?? "" : "";
                return factory(entity, name);
            }
        }
        catch (Exception ex)
        {
            s_pendingException ??= ex;
        }
        return false;
    }

    /// <summary>Also releases the GC handle kept for the registered script factory.</summary>
    partial void OnDispose()
    {
        if (_scriptHandle.IsAllocated) _scriptHandle.Free();
        _scriptClosure = null;
    }
}
