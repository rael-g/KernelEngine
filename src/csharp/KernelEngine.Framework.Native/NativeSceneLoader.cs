using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Framework.Native;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_scene_loader</c> primitive. The C plugin handles
/// TOML parsing, nested scene resolution, transforms, and property dispatch via
/// <c>ke_node_type_registry</c> callbacks. The C# shell only owns the unmanaged handle and
/// presents the path-string ABI in a managed-friendly form.
/// </summary>
internal sealed unsafe class NativeSceneLoader : ISceneLoaderBackend
{
    // Per-language factory storage — the trampoline retrieves the closure via
    // GCHandle from the loader-instance handle pointer. One trampoline serves
    // every language; the loader's `ctx` discriminates which closure to call.
    private record struct Registered(GCHandle Handle, Func<ulong, string, bool> Closure);
    private readonly System.Collections.Generic.List<Registered> _scriptHandles = new();

    private ke_scene_loader* _native;

    public NativeSceneLoader(Allocator allocator,
                              World world,
                              NativeSceneTree tree,
                              string? projectRoot)
    {
        ke_scene_loader* p;
        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        // ke_world is opaque to this plugin binding; cross-cast across Kernel.Native / Framework.Native
        // generated identities (both reference the same C struct).
        var worldFw = (KernelEngine.Framework.Native.ke_world*)world.Native;
        fixed (byte* rootPtr = rootBytes)
        {
            KernelException.ThrowIfFailed(
                KernelEngine.Framework.Native.NativeMethods.scene_loader_create(
                    allocator.Native,
                    worldFw,
                    tree.NativePtr,
                    null,                 // registry: dropped in Phase 5.6 (legacy node-type registry deleted)
                    (sbyte*)rootPtr,
                    &p).ToManaged());
        }
        _native = p;
    }

    public void Load(string path)
    {
        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        s_pendingException = null;
        ke_result result;
        fixed (byte* p = bytes)
        {
            result = _native->load(_native, (sbyte*)p);
        }
        // A managed exception inside the script trampoline was captured
        // out-of-band; rethrow it now that the native stack has unwound.
        if (s_pendingException is { } pending)
        {
            s_pendingException = null;
            throw pending;
        }
        KernelException.ThrowIfFailed(result.ToManaged());
    }

    // Pending exception slot for any managed throw that occurs inside the
    // ScriptTrampoline. Cleared at the start of every Load.
    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void InitPendingException() => s_pendingException = null;
    private static System.Exception? s_pendingException;

    public void RegisterScriptLanguage(string language, Func<ulong, string, bool> factory)
    {
        ArgumentNullException.ThrowIfNull(language);
        ArgumentNullException.ThrowIfNull(factory);
        if (_native is null) throw new ObjectDisposedException(nameof(NativeSceneLoader));

        // Pin the closure under a GCHandle so the native side can call back into
        // managed code (the ctx pointer is the handle). The handle is released in
        // Dispose so each loader instance owns its closures' lifetime.
        var gch = GCHandle.Alloc(factory);
        _scriptHandles.Add(new Registered(gch, factory));
        var ctx = GCHandle.ToIntPtr(gch);

        var bytes = Encoding.UTF8.GetBytes(language + "\0");
        fixed (byte* p = bytes)
        {
            var rc = _native->register_script_language(_native, (sbyte*)p,
                &ScriptTrampoline, (void*)ctx);
            KernelException.ThrowIfFailed(rc.ToManaged());
        }
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
                return factory(entity, name) ? ke_result.KE_OK : ke_result.KE_ERROR_NOT_FOUND;
            }
        }
        catch (Exception ex)
        {
            // Surface managed exceptions: store and rethrow once the native
            // stack has unwound (the C plugin can't propagate managed throws).
            s_pendingException ??= ex;
        }
        return ke_result.KE_ERROR;
    }

    public void Dispose()
    {
        if (_native is not null)
        {
            _native->destroy(_native);
            _native = null;
        }
        foreach (var r in _scriptHandles) r.Handle.Free();
        _scriptHandles.Clear();
    }
}
