using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Framework.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_input_actions</c> vtable. The C plugin
/// handles TOML parsing and per-frame binding evaluation against a
/// <c>ke_input_snapshot</c>. This shell owns the unmanaged handle and presents
/// the action-string ABI in a managed-friendly form.
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
/// <see cref="Load"/> clears all previous actions and re-assigns ids from 0.
/// </remarks>
public sealed unsafe class NativeInputActions : IDisposable
{
    private ke_input_actions* _native;

    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void InitPendingException() => s_pendingException = null;
    private static Exception? s_pendingException;

    private GCHandle _eventHandle;
    private Action<ke_input_action_event>? _eventClosure;

    /// <summary>Creates a native input-actions instance.</summary>
    public NativeInputActions()
    {
        ke_input_actions* p;
        KernelException.ThrowIfFailed(
            KernelEngine.Framework.Native.NativeMethods.input_actions_create(&p, null).ToManaged());
        _native = p;
    }

    /// <summary>
    /// Loads action bindings from a <c>.input</c> TOML file at <paramref name="path"/>.
    /// Clears any previously-registered actions.
    /// </summary>
    /// <exception cref="FileNotFoundException">File does not exist.</exception>
    /// <exception cref="KernelException">Parse or other native failure.</exception>
    public void Load(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentException.ThrowIfNullOrEmpty(path);
        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        ke_result result;
        fixed (byte* p = bytes)
            result = _native->load(_native, (sbyte*)p, null);
        KernelException.ThrowIfFailed(result.ToManaged());
    }

    /// <summary>
    /// Resolves an action name to its runtime integer id, or -1 if unknown.
    /// Cache the id; don't call this per frame.
    /// </summary>
    public int GetActionId(string name)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentException.ThrowIfNullOrEmpty(name);
        var bytes = Encoding.UTF8.GetBytes(name + "\0");
        fixed (byte* p = bytes)
            return _native->get_action_id(_native, (sbyte*)p);
    }

    /// <summary>
    /// Registers a new action by name and returns its assigned id, or -1 on failure.
    /// Must be called after <see cref="Load"/> when mixing file + programmatic registration.
    /// </summary>
    public int AddAction(string name, ke_action_type type)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentException.ThrowIfNullOrEmpty(name);
        var bytes = Encoding.UTF8.GetBytes(name + "\0");
        fixed (byte* p = bytes)
            return _native->add_action(_native, (sbyte*)p, type);
    }

    /// <summary>Attaches a single-key Button binding to <paramref name="actionId"/>.</summary>
    public void BindKey(int actionId, ke_key key)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        KernelException.ThrowIfFailed(_native->bind_key(_native, actionId, key, null).ToManaged());
    }

    /// <summary>Attaches a mouse-button Button binding to <paramref name="actionId"/>.</summary>
    public void BindMouseButton(int actionId, ke_mouse_button button)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        KernelException.ThrowIfFailed(
            _native->bind_mouse_button(_native, actionId, button, null).ToManaged());
    }

    /// <summary>
    /// Attaches an Axis1D binding: <paramref name="negative"/> emits −1,
    /// <paramref name="positive"/> emits +1, both held cancels to 0.
    /// </summary>
    public void BindKeyPair(int actionId, ke_key negative, ke_key positive)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        KernelException.ThrowIfFailed(
            _native->bind_key_pair(_native, actionId, negative, positive, null).ToManaged());
    }

    /// <summary>
    /// Attaches an Axis2D binding from four directional keys.
    /// X = right − left, Y = up − down.
    /// </summary>
    public void BindKeyQuad(int actionId, ke_key up, ke_key down, ke_key left, ke_key right)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        KernelException.ThrowIfFailed(
            _native->bind_key_quad(_native, actionId, up, down, left, right, null).ToManaged());
    }

    /// <summary>
    /// Runs one frame of binding evaluation against <paramref name="snapshot"/>,
    /// updating polling state and firing <paramref name="onEvent"/> for each phase transition.
    /// Pass <see langword="null"/> for <paramref name="onEvent"/> to update polling only.
    /// </summary>
    public void Evaluate(ke_input_snapshot* snapshot, Action<ke_input_action_event>? onEvent = null)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);

        void* ctx = null;

        if (onEvent is not null)
        {
            if (_eventHandle.IsAllocated) _eventHandle.Free();
            _eventClosure = onEvent;
            _eventHandle = GCHandle.Alloc(onEvent);
            ctx = (void*)GCHandle.ToIntPtr(_eventHandle);
        }

        s_pendingException = null;
        ke_result result;
        if (onEvent is not null)
            result = _native->evaluate(_native, snapshot, &EventTrampoline, ctx, null);
        else
            result = _native->evaluate(_native, snapshot, null, null, null);

        if (s_pendingException is { } pending) { s_pendingException = null; throw pending; }
        KernelException.ThrowIfFailed(result.ToManaged());
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

    /// <summary>True while the action's combined value is active this frame.</summary>
    public bool IsActionDown(int actionId)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        return _native->is_action_down(_native, actionId);
    }

    /// <summary>True for exactly the first frame the action became active.</summary>
    public bool WasActionPressed(int actionId)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        return _native->was_action_pressed(_native, actionId);
    }

    /// <summary>True for exactly the first frame the action became inactive.</summary>
    public bool WasActionReleased(int actionId)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        return _native->was_action_released(_native, actionId);
    }

    /// <summary>Returns the current Axis1D value for <paramref name="actionId"/>.</summary>
    public float GetAxis1D(int actionId)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        return _native->get_axis1d(_native, actionId);
    }

    /// <summary>Returns the current Axis2D value for <paramref name="actionId"/>.</summary>
    public (float X, float Y) GetAxis2D(int actionId)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        float x, y;
        _native->get_axis2d(_native, actionId, &x, &y);
        return (x, y);
    }

    /// <summary>Returns the current Axis3D value for <paramref name="actionId"/>.</summary>
    public (float X, float Y, float Z) GetAxis3D(int actionId)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        float x, y, z;
        _native->get_axis3d(_native, actionId, &x, &y, &z);
        return (x, y, z);
    }

    /// <inheritdoc cref="IDisposable.Dispose"/>
    public void Dispose()
    {
        if (_native is not null) { _native->destroy(_native); _native = null; }
        if (_eventHandle.IsAllocated) _eventHandle.Free();
        _eventClosure = null;
    }
}
