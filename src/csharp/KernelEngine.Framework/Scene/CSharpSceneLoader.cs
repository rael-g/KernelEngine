using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Tier S round-trip implementation of <see cref="ISceneLoader"/> and <c>ke_scene_loader</c>.
/// <para>
/// Delegates to <see cref="SceneLoader.LoadAsync"/> (the existing C# reflection-based loader)
/// while also wiring the native <c>ke_scene_loader</c> vtable so non-.NET callers (e.g. a future
/// C++ host) can drive the same implementation through the C ABI. Once a native TOML plugin
/// replaces this class, the Framework is demoted back to <c>AllowUnsafeBlocks=false</c>.
/// </para>
/// </summary>
internal sealed unsafe class CSharpSceneLoader : ISceneLoader, IDisposable
{
    private ke_scene_loader* _native;
    private GCHandle _selfHandle;
    private bool _disposed;

    private readonly Tree _tree;
    private readonly ResourceManager _resources;
    private readonly IServiceProvider? _services;

    public CSharpSceneLoader(Tree tree, ResourceManager resources, IServiceProvider? services = null)
    {
        _tree      = tree;
        _resources = resources;
        _services  = services;

        _selfHandle = GCHandle.Alloc(this);

        // Allocate the vtable struct in unmanaged heap so the pointer is stable across GC moves.
        _native = (ke_scene_loader*)NativeMemory.Alloc((nuint)sizeof(ke_scene_loader));
        *_native = new ke_scene_loader
        {
            handle  = (void*)GCHandle.ToIntPtr(_selfHandle),
            load    = &NativeLoad,
            destroy = &NativeDestroy,
        };
    }

    /// <summary>The stable native pointer — valid for the lifetime of this object.</summary>
    public ke_scene_loader* Native => _native;

    // ── ISceneLoader ──────────────────────────────────────────────────────────

    /// <inheritdoc/>
    public Task LoadAsync(string path) =>
        SceneLoader.LoadAsync(_tree, path, _resources, _services);

    // ── Trampolines (called by C or future native callers through the vtable) ─

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeLoad(ke_scene_loader* self, sbyte* path)
    {
        try
        {
            var loader = (CSharpSceneLoader)GCHandle.FromIntPtr((nint)self->handle).Target!;
            var pathStr = Marshal.PtrToStringUTF8((nint)path)
                ?? throw new ArgumentNullException(nameof(path));
            loader.LoadAsync(pathStr).GetAwaiter().GetResult();
            return ke_result.KE_OK;
        }
        catch
        {
            return ke_result.KE_ERROR;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeDestroy(ke_scene_loader* self)
    {
        // Managed lifetime is controlled by IDisposable — native destroy is a no-op here.
        // A future C++ plugin would free its own resources; the bridge defers to Dispose().
    }

    // ── IDisposable ───────────────────────────────────────────────────────────

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_native != null) { NativeMemory.Free(_native); _native = null; }
        if (_selfHandle.IsAllocated) _selfHandle.Free();
    }
}
