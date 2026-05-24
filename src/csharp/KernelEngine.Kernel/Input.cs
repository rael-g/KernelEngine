using System.Numerics;

using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Tracks keyboard and mouse state. Reads messages from the <see cref="MessagePipe"/>.
/// </summary>
public sealed unsafe class Input : IInput
{
    // ── Static Access ────────────────────────────────────────────────────────

    [ThreadStatic]
    private static IInputReader? s_currentReader;

    /// <summary>
    /// Accesses the input snapshot for the current frame.
    /// Available during <see cref="ISystem.Update"/> and <see cref="Node.OnUpdate"/>.
    /// </summary>
    public static IInputReader Current => s_currentReader ?? throw new InvalidOperationException("Input.Current is only available during the simulation update.");

    internal static void SetCurrentReader(IInputReader? reader) => s_currentReader = reader;

    // ── Instance members ──────────────────────────────────────────────────────

    private ke_input* _native;

    public ke_input* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    public Input(Allocator allocator, Logger? logger)
    {
        ke_input* native;
        var res = NativeMethods.input_create(
            allocator.Native,
            logger != null ? logger.Native : null,
            &native);

        KernelException.ThrowIfFailed(res.ToManaged(), nameof(NativeMethods.input_create));
        _native = native;
    }

    /// <summary>Updates internal state by processing pending messages in the pipe.</summary>
    public Result Update()
    {
        KernelThread.AssertCurrent("ke.main");
        return _native->update(_native).Wrap();
    }

    /// <summary>Captures a frozen snapshot of the current input state (native form).</summary>
    public ke_input_snapshot GetSnapshot()
    {
        KernelThread.AssertCurrent("ke.main");
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

    /// <summary>Returns true if the key was pressed this frame.</summary>
    public bool IsKeyPressed(int key) => _native->is_key_pressed(_native, key) != 0;

    /// <summary>Returns true if the key was released this frame.</summary>
    public bool IsKeyReleased(int key) => _native->is_key_released(_native, key) != 0;

    /// <summary>Returns true if the key is currently held down.</summary>
    public bool IsKeyDown(int key) => _native->is_key_down(_native, key) != 0;

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
