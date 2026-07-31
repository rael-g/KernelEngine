using System.Runtime.InteropServices;
using KernelEngine.Common;
using KernelEngine.Common.Native;
using KernelEngine.Input.Native;

namespace KernelEngine.Framework;

/// <summary>
/// The parts of <see cref="NativeInputActions"/> that are not a direct image of the C
/// ABI: the constructor's factory call, and <see cref="Evaluate"/>'s GCHandle/trampoline
/// bridging plus pending-exception rethrow for the bare <c>[raw_callback]</c> function
/// pointer — a managed <see cref="Action{T}"/> handler can throw mid-native-call; the
/// trampoline catches it and this rethrows once the native stack has unwound, which has
/// no ABI-derivable shape. Everything that mirrors the vtable 1:1 is generated in
/// <c>Generated/NativeInputActions.g.cs</c>.
/// </summary>
/// <remarks>
/// Typical usage:
/// <code>
/// using var actions = new NativeInputActions();
/// actions.Load("res://input/player.input");
/// int moveId  = actions.GetActionId("Move");
/// int jumpId  = actions.GetActionId("Jump");
///
/// // each tick, after polling input:
/// actions.Evaluate(snapshot);
/// float axis = actions.GetAxis1D(moveId);
/// if (actions.WasActionPressed(jumpId)) { /* … */ }
/// </code>
/// Action ids are stable for the lifetime of the loaded file. Re-calling
/// <see cref="NativeInputActions.Load"/> clears all previous actions and re-assigns ids from 0.
/// </remarks>
public unsafe partial class NativeInputActions
{
    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void InitPendingException() => s_pendingException = null;
    private static Exception? s_pendingException;
    private GCHandle _eventHandle;
    private Action<ke_input_action_event>? _eventClosure;

    /// <summary>Creates a native input-actions instance.</summary>
    public NativeInputActions() : this(Create())
    {
    }

    private static ke_input_actions_handle Create()
    {
        ke_error* err = null;
        var handle = KernelEngine.Framework.Native.NativeMethods.input_actions_create(&err);
        if (handle.@ref == null) throw KernelError.FromNative(err, "input_actions_create");
        return handle;
    }

    /// <summary>
    /// Runs one frame of binding evaluation against <paramref name="snapshot"/>,
    /// updating polling state and firing <paramref name="onEvent"/> for each phase transition.
    /// Pass <see langword="null"/> for <paramref name="onEvent"/> to update polling only.
    /// </summary>
    public void Evaluate(ke_input_snapshot* snapshot, Action<ke_input_action_event>? onEvent = null)
    {
        var native = ((INativeInputActions)this).Native;
        void* ctx = null;

        if (onEvent is not null)
        {
            if (_eventHandle.IsAllocated) _eventHandle.Free();
            _eventClosure = onEvent;
            _eventHandle = GCHandle.Alloc(onEvent);
            ctx = (void*)GCHandle.ToIntPtr(_eventHandle);
        }

        s_pendingException = null;
        ke_error* err = null;
        bool result;
        if (onEvent is not null)
            result = native->evaluate(native, snapshot, &EventTrampoline, ctx, &err);
        else
            result = native->evaluate(native, snapshot, null, null, &err);

        if (s_pendingException is { } pending) { s_pendingException = null; throw pending; }
        KernelError.ThrowIfFailed(result, err, "evaluate");
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static void EventTrampoline(void* ctx, ke_input_action_event ev)
    {
        try
        {
            var gch = GCHandle.FromIntPtr((IntPtr)ctx);
            if (gch.Target is Action<ke_input_action_event> handler)
                handler(ev);
        }
        catch (Exception ex)
        {
            s_pendingException ??= ex;
        }
    }

    /// <summary>Also releases the GC handle kept for the registered event callback.</summary>
    partial void OnDispose()
    {
        if (_eventHandle.IsAllocated) _eventHandle.Free();
        _eventClosure = null;
    }
}
