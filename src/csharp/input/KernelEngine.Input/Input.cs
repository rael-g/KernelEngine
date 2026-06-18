using System.Numerics;

using KernelEngine.Kernel.Native;
using InputNative = KernelEngine.Input.Native.NativeMethods;

namespace KernelEngine.Kernel;

/// <summary>
/// Tracks keyboard and mouse state. Reads messages from the <see cref="MessagePipe"/>.
/// </summary>
public sealed unsafe class Input : IInput, INativeInput
{
    // Per-frame current-reader accessor moved to KernelEngine.Kernel.InputContext (Abstractions) so
    // the Framework can set it without referencing this concrete. Game code that polled Input.Current
    // should switch to InputContext.Current.

    // ── Instance members ──────────────────────────────────────────────────────

    private ke_input* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_input*, void> _destroy;

    public ke_input* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    public Input(INativeLogger? logger)
    {
        ke_input_handle handle;
        var res = InputNative.input_create(
            logger != null ? logger.Native : null,
            &handle, null);

        KernelException.ThrowIfFailed(res.ToManaged(), nameof(InputNative.input_create));
        _native = handle.@ref;
        _destroy = handle.destroy;
    }

    /// <summary>Updates internal state by processing pending messages in the pipe.</summary>
    /// <remarks>
    /// Caller is responsible for serializing Update with reads (the runtime
    /// pins these to a single worker via system phase ordering). The previous
    /// hard-coded <c>ke.main</c> affinity check was tied to the legacy single-
    /// main-thread model and no longer fits the module-driven runtime.
    /// </remarks>
    public Result Update()
    {
        return _native->update(_native, null).Wrap();
    }

    /// <summary>Captures a frozen snapshot of the current input state (native form).</summary>
    public ke_input_snapshot GetSnapshot()
    {
        ke_input_snapshot snapshot;
        _native->get_snapshot(_native, &snapshot);
        return snapshot;
    }

    /// <inheritdoc/>
    public IInputReader CaptureSnapshot() => new InputSnapshotReader(GetSnapshot());

    /// <inheritdoc/>
    public int DrainEvents(Span<InputEvent> buffer)
    {
        KernelThread.AssertCurrent("ke.main");
        if (buffer.IsEmpty) return 0;

        // Stage into a native-shaped buffer, then translate. The native struct is identical
        // in layout to InputEvent's discriminated fields, but we go through translation to
        // map ke_input_event_kind → InputEventKind and split code into Key vs Button.
        Span<ke_input_event> native = stackalloc ke_input_event[buffer.Length];
        uint count;
        fixed (ke_input_event* p = native)
            count = _native->drain_events(_native, p, (uint)buffer.Length);

        for (int i = 0; i < count; i++)
        {
            ref readonly var n = ref native[i];
            ref var dst = ref buffer[i];
            dst.Handled = false;
            switch (n.kind)
            {
                case ke_input_event_kind.KE_INPUT_EVENT_KEY_DOWN:
                    dst.Kind = InputEventKind.KeyDown;
                    dst.Key = (Key)n.code;
                    break;
                case ke_input_event_kind.KE_INPUT_EVENT_KEY_UP:
                    dst.Kind = InputEventKind.KeyUp;
                    dst.Key = (Key)n.code;
                    break;
                case ke_input_event_kind.KE_INPUT_EVENT_MOUSE_BUTTON_DOWN:
                    dst.Kind = InputEventKind.MouseButtonDown;
                    dst.Button = (MouseButton)n.code;
                    break;
                case ke_input_event_kind.KE_INPUT_EVENT_MOUSE_BUTTON_UP:
                    dst.Kind = InputEventKind.MouseButtonUp;
                    dst.Button = (MouseButton)n.code;
                    break;
                case ke_input_event_kind.KE_INPUT_EVENT_MOUSE_SCROLL:
                    dst.Kind = InputEventKind.MouseScroll;
                    dst.Scroll = new Vector2(n.x, n.y);
                    break;
                default:
                    dst.Kind = InputEventKind.None;
                    break;
            }
        }
        return (int)count;
    }

    /// <summary>Returns true if the key is currently held down.</summary>
    public bool IsKeyDown(int key) => _native->is_key_down(_native, key) != 0;

    public void Dispose()
    {
        if (_native != null)
        {
            if (_destroy != null) _destroy(_native);
            _native = null;
        }
    }
}
