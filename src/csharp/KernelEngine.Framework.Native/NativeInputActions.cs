using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Framework.Native;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_input_actions</c> primitive provided by
/// the <c>ke_framework</c> plugin. Owns the unmanaged handle, the name strings
/// passed across the ABI boundary, and the per-frame event buffer used by
/// <see cref="Evaluate"/>.
/// </summary>
/// <remarks>
/// Game code never touches this class directly — it sits behind
/// <see cref="InputActionMap{TEnum}"/>. Exposed as <c>internal</c> so the
/// Framework dispatcher loop and tests can drive it.
/// </remarks>
internal sealed unsafe class NativeInputActions : IInputActionsBackend
{
    private ke_input_actions* _native;
    private readonly List<IntPtr> _nameStrings = new();
    private readonly GCHandle _eventBufferHandle;
    private readonly List<InputActionEvent> _frameEvents = new(32);
    private Type? _enumType;

    public NativeInputActions(Allocator allocator)
    {
        ke_input_actions* p;
        KernelException.ThrowIfFailed(
            KernelEngine.Framework.Native.NativeMethods.input_actions_create(allocator.Native, &p).ToManaged());
        _native = p;
        _eventBufferHandle = GCHandle.Alloc(this);
    }

    /// <summary>
    /// CLR type of the game's action enum this map is bound to. Used by the
    /// dispatcher to tag events.
    /// </summary>
    public Type EnumType
    {
        get => _enumType ?? throw new InvalidOperationException("EnumType not set.");
        set => _enumType = value;
    }

    /// <summary>
    /// Registers an action by name. Returns the assigned action_id (>= 0).
    /// Throws on duplicate name.
    /// </summary>
    public int AddAction(string name, ActionType type)
    {
        var bytes = Encoding.UTF8.GetBytes(name + "\0");
        IntPtr str = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, str, bytes.Length);
        _nameStrings.Add(str);

        int id = _native->add_action(_native, (sbyte*)str, (ke_action_type)(int)type);
        if (id < 0)
            throw new ArgumentException($"Action '{name}' is already registered.");
        return id;
    }

    public void BindKey(int actionId, Key key) =>
        KernelException.ThrowIfFailed(
            _native->bind_key(_native, actionId, (ke_key)(int)key).ToManaged());

    public void BindMouseButton(int actionId, MouseButton button) =>
        KernelException.ThrowIfFailed(
            _native->bind_mouse_button(_native, actionId, (ke_mouse_button)(int)button).ToManaged());

    public void BindKeyPair(int actionId, Key negative, Key positive) =>
        KernelException.ThrowIfFailed(
            _native->bind_key_pair(_native, actionId,
                (ke_key)(int)negative, (ke_key)(int)positive).ToManaged());

    public void BindKeyQuad(int actionId, Key up, Key down, Key left, Key right) =>
        KernelException.ThrowIfFailed(
            _native->bind_key_quad(_native, actionId,
                (ke_key)(int)up, (ke_key)(int)down,
                (ke_key)(int)left, (ke_key)(int)right).ToManaged());

    public void Load(string path)
    {
        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        fixed (byte* p = bytes)
        {
            KernelException.ThrowIfFailed(
                _native->load(_native, (sbyte*)p).ToManaged());
        }
    }

    public int GetActionId(string name)
    {
        var bytes = Encoding.UTF8.GetBytes(name + "\0");
        fixed (byte* p = bytes)
        {
            return _native->get_action_id(_native, (sbyte*)p);
        }
    }

    public bool IsActionDown(int id)        => _native->is_action_down(_native, id) != 0;
    public bool WasActionPressed(int id)    => _native->was_action_pressed(_native, id) != 0;
    public bool WasActionReleased(int id)   => _native->was_action_released(_native, id) != 0;

    public float GetAxis1D(int id) => _native->get_axis1d(_native, id);

    public System.Numerics.Vector2 GetAxis2D(int id)
    {
        float x = 0, y = 0;
        _native->get_axis2d(_native, id, &x, &y);
        return new System.Numerics.Vector2(x, y);
    }

    public System.Numerics.Vector3 GetAxis3D(int id)
    {
        float x = 0, y = 0, z = 0;
        _native->get_axis3d(_native, id, &x, &y, &z);
        return new System.Numerics.Vector3(x, y, z);
    }

    /// <summary>
    /// Evaluates all registered actions against the snapshot and appends every
    /// phase-transition event (Started / Performed / Canceled) to <paramref name="output"/>.
    /// </summary>
    public void Evaluate(IInputReader snapshot, List<InputActionEvent> output)
    {
        // The native plugin reads the kernel ke_input_snapshot struct; concrete InputSnapshotReader
        // exposes it. Custom IInputReader impls (tests, synthetic) fall through to a no-op since
        // the action dispatcher has no portable way to sample arbitrary managed readers.
        if (snapshot is not InputSnapshotReader nativeReader) return;
        var nativeSnap = nativeReader.Native;
        _frameEvents.Clear();
        IntPtr ctx = GCHandle.ToIntPtr(_eventBufferHandle);
        KernelException.ThrowIfFailed(
            _native->evaluate(_native, &nativeSnap, &OnEventTrampoline, (void*)ctx).ToManaged());
        output.AddRange(_frameEvents);
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static void OnEventTrampoline(void* ctx, ke_input_action_event ev)
    {
        var self = (NativeInputActions?)GCHandle.FromIntPtr((IntPtr)ctx).Target;
        if (self is null) return;
        self._frameEvents.Add(new InputActionEvent
        {
            EnumType = self._enumType!,
            ActionId = ev.action_id,
            Type     = (ActionType)(int)ev.type,
            Phase    = (ActionPhase)(int)ev.phase,
            ValueX   = ev.x,
            ValueY   = ev.y,
            ValueZ   = ev.z,
        });
    }

    public void Dispose()
    {
        if (_native is not null)
        {
            _native->destroy(_native);
            _native = null;
        }
        foreach (var p in _nameStrings) Marshal.FreeHGlobal(p);
        _nameStrings.Clear();
        if (_eventBufferHandle.IsAllocated) _eventBufferHandle.Free();
    }
}
