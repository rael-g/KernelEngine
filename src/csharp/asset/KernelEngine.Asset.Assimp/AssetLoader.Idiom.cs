using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Common;
using KernelEngine.Scheduler;

namespace KernelEngine.Asset.Assimp;

/// <summary>
/// The parts of <see cref="AssetLoader"/> that express the native surface in C# terms
/// rather than mirroring it: the <see cref="IModel"/> projection over a raw
/// <c>ke_model_data*</c>, and the <c>Task</c>-returning async load — <c>load_model_async</c>
/// takes a bare C function pointer (<c>[raw_callback]</c>), so there is no ABI-derivable
/// answer for what the managed async surface should look like; this is entirely
/// hand-written, like every other <c>[raw_callback]</c> slot in this codebase.
/// Everything that is a direct image of the C ABI is generated in <c>Generated/AssetLoader.g.cs</c>.
/// </summary>
public unsafe partial class AssetLoader : IAssetLoader
{
    private readonly KernelEngine.Scheduler.Scheduler _scheduler;

    /// <summary>Wraps an owner <c>ke_asset_loader_handle</c>, keeping the scheduler <c>LoadModelAsync</c> dispatches onto.</summary>
    public AssetLoader(ke_asset_loader_handle handle, KernelEngine.Scheduler.Scheduler scheduler) : this(handle)
    {
        _scheduler = scheduler;
    }

    /// <inheritdoc/>
    IModel IAssetLoader.LoadModel(string path)
    {
        var data = LoadModel(path);
        return new ModelData((ke_asset_loader*)((INativeAssetLoader)this).Native, data);
    }

    /// <inheritdoc/>
    public Task<IModel> LoadModelAsync(string path)
    {
        var native = ((INativeAssetLoader)this).Native;
        var tcs = new TaskCompletionSource<IModel>(TaskCreationOptions.RunContinuationsAsynchronously);

        var state = ((nint)native, tcs);
        var stateHandle = GCHandle.Alloc(state);

        var pathBytes = System.Text.Encoding.UTF8.GetBytes(path + '\0');
        fixed (byte* pathPtr = pathBytes)
        {
            native->load_model_async(
                native,
                ((INativeScheduler)_scheduler).Native,
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
        var (loaderPtr, tcs) = ((nint, TaskCompletionSource<IModel>))handle.Target!;
        handle.Free();

        if (error == null && data != null)
            tcs.TrySetResult(new ModelData((ke_asset_loader*)loaderPtr, data));
        else
            tcs.TrySetException(KernelError.FromNative(error, "load_model_async"));
    }
}
