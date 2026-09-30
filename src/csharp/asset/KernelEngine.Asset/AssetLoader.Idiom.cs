using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Common;
using KernelEngine.Scheduler;

namespace KernelEngine.Asset;

/// <summary>
/// The part of <see cref="AssetLoader"/> that expresses the native surface in C# terms
/// rather than mirroring it: the <c>Task</c>-returning async load. <c>load_model_async</c>
/// takes a bare C function pointer (<c>[raw_callback]</c>), so there is no ABI-derivable
/// answer for what the managed async surface should look like; this is written by hand,
/// like every other <c>[raw_callback]</c> slot in this codebase. Everything that is a
/// direct image of the C ABI is generated in <c>Generated/AssetLoader.g.cs</c>.
/// </summary>
public unsafe partial class AssetLoader
{
    private readonly INativeScheduler _scheduler;

    /// <summary>Wraps an owner <c>ke_asset_loader_handle</c>, keeping the scheduler <c>LoadModelAsync</c> dispatches onto.</summary>
    public AssetLoader(ke_asset_loader_handle handle, INativeScheduler scheduler) : this(handle)
    {
        _scheduler = scheduler;
    }

    /// <summary>
    /// Loads a model asynchronously on the engine's task scheduler.
    /// Caller disposes the returned <see cref="Model"/>.
    /// </summary>
    public Task<Model> LoadModelAsync(string path)
    {
        var native = ((INativeAssetLoader)this).Native;
        var tcs = new TaskCompletionSource<Model>(TaskCreationOptions.RunContinuationsAsynchronously);

        var state = (this, tcs);
        var stateHandle = GCHandle.Alloc(state);

        var pathBytes = System.Text.Encoding.UTF8.GetBytes(path + '\0');
        fixed (byte* pathPtr = pathBytes)
        {
            native->load_model_async(
                native,
                _scheduler.Native,
                (sbyte*)pathPtr,
                &NativeLoadCompleteCallback,
                (void*)GCHandle.ToIntPtr(stateHandle));
        }

        return tcs.Task;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe void NativeLoadCompleteCallback(
        ke_error* error,
        ke_model_data* data,
        void* userData)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        var (loader, tcs) = ((AssetLoader, TaskCompletionSource<Model>))handle.Target!;
        handle.Free();

        if (error == null && data != null)
            tcs.TrySetResult(new Model(loader, (ModelData*)data));
        else
            tcs.TrySetException(KernelError.FromNative(error, "load_model_async"));
    }
}
