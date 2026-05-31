using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Tier S round-trip implementation of the <c>ke_input_actions</c> kernel contract.
/// <para>
/// Delegates to <see cref="InputActionDispatcher"/> and <see cref="InputActions.AllMaps"/>
/// (the existing C# action system) while wiring the native vtable so non-.NET callers
/// can drive evaluation and polling through the C ABI. Once a native C++ plugin provides
/// its own <c>ke_input_actions</c>, this bridge is discarded and the Framework stops
/// owning input-action vtable structs.
/// </para>
/// </summary>
internal sealed unsafe class CSharpInputActions : IDisposable
{
    private ke_input_actions* _native;
    private GCHandle _selfHandle;
    private bool _disposed;

    private readonly InputActionDispatcher _dispatcher;

    public CSharpInputActions(InputActionDispatcher dispatcher)
    {
        _dispatcher  = dispatcher;
        _selfHandle  = GCHandle.Alloc(this);

        _native = (ke_input_actions*)NativeMemory.Alloc((nuint)sizeof(ke_input_actions));
        *_native = new ke_input_actions
        {
            handle              = (void*)GCHandle.ToIntPtr(_selfHandle),
            load                = &NativeLoad,
            evaluate            = &NativeEvaluate,
            is_action_down      = &NativeIsActionDown,
            was_action_pressed  = &NativeWasActionPressed,
            was_action_released = &NativeWasActionReleased,
            get_axis1d          = &NativeGetAxis1D,
            get_axis2d          = &NativeGetAxis2D,
            get_axis3d          = &NativeGetAxis3D,
            destroy             = &NativeDestroy,
        };
    }

    public ke_input_actions* Native => _native;

    // ── Managed dispatch (called by Application) ──────────────────────────────

    public List<InputActionEvent> Evaluate(IInputReader reader) =>
        _dispatcher.Evaluate(reader);

    // ── Trampolines ───────────────────────────────────────────────────────────

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeLoad(ke_input_actions* self, sbyte* path)
    {
        // Loading is still driven from C# (InputActionsLoader). In S4 the load slot
        // exists in the contract so a future C++ plugin can implement it. No-op here.
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeEvaluate(
        ke_input_actions* self,
        ke_input_snapshot* snapshot,
        delegate* unmanaged[Cdecl]<void*, ke_input_action_event, void> on_event,
        void* event_ctx)
    {
        try
        {
            var bridge = (CSharpInputActions)GCHandle.FromIntPtr((nint)self->handle).Target!;

            // Wrap the native snapshot in a managed reader so the dispatcher can sample bindings.
            var reader = new NativeSnapshotReader(snapshot);
            var events = bridge._dispatcher.Evaluate(reader);

            if (on_event != null)
            {
                foreach (var e in events)
                {
                    var native = new ke_input_action_event
                    {
                        action_id = e.ActionId,
                        type      = (ke_action_type)(int)e.Type,
                        phase     = (ke_action_phase)(int)e.Phase,
                        x         = e.ValueX,
                        y         = e.ValueY,
                        z         = e.ValueZ,
                    };
                    on_event(event_ctx, native);
                }
            }
            return ke_result.KE_OK;
        }
        catch
        {
            return ke_result.KE_ERROR;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool NativeIsActionDown(ke_input_actions* self, int actionId) =>
        FindAction(self, actionId) is { } a && a.IsActiveNow;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool NativeWasActionPressed(ke_input_actions* self, int actionId) =>
        FindAction(self, actionId) is { } a && !a.WasActivePrev && a.IsActiveNow;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool NativeWasActionReleased(ke_input_actions* self, int actionId) =>
        FindAction(self, actionId) is { } a && a.WasActivePrev && !a.IsActiveNow;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static float NativeGetAxis1D(ke_input_actions* self, int actionId) =>
        FindAction(self, actionId)?.CurrX ?? 0f;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeGetAxis2D(ke_input_actions* self, int actionId, float* x, float* y)
    {
        var a = FindAction(self, actionId);
        if (x != null) *x = a?.CurrX ?? 0f;
        if (y != null) *y = a?.CurrY ?? 0f;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeGetAxis3D(ke_input_actions* self, int actionId, float* x, float* y, float* z)
    {
        var a = FindAction(self, actionId);
        if (x != null) *x = a?.CurrX ?? 0f;
        if (y != null) *y = a?.CurrY ?? 0f;
        if (z != null) *z = a?.CurrZ ?? 0f;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeDestroy(ke_input_actions* self) { /* managed lifetime via IDisposable */ }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static InputAction? FindAction(ke_input_actions* self, int actionId)
    {
        foreach (var map in InputActions.AllMaps)
            foreach (var action in map.Actions)
                if (action.ActionId == actionId) return action;
        return null;
    }

    // ── IDisposable ───────────────────────────────────────────────────────────

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_native != null) { NativeMemory.Free(_native); _native = null; }
        if (_selfHandle.IsAllocated) _selfHandle.Free();
    }

    // ── NativeSnapshotReader ──────────────────────────────────────────────────
    // Wraps a ke_input_snapshot* as an IInputReader so the existing dispatcher can sample it.

    private sealed unsafe class NativeSnapshotReader(ke_input_snapshot* snap) : IInputReader
    {
        public bool IsKeyDown(int keyCode)
        {
            if (keyCode < 0 || keyCode >= 512) return false;
            int word = keyCode / 64, bit = keyCode % 64;
            return (snap->keys_down[word] & (1UL << bit)) != 0;
        }

        public bool IsMouseButtonDown(int button) =>
            (snap->mouse_buttons_down & (1u << button)) != 0;

        public System.Numerics.Vector2 MousePosition =>
            new(snap->mouse_x, snap->mouse_y);

        public System.Numerics.Vector2 MouseDelta =>
            new(snap->mouse_dx, snap->mouse_dy);

        public System.Numerics.Vector2 ScrollDelta =>
            new(snap->scroll_dx, snap->scroll_dy);
    }
}
