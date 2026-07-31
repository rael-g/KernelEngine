using System.Numerics;
using KernelEngine.Common.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger;

namespace KernelEngine.Input;

/// <summary>
/// The parts of <see cref="Input"/> that express the native surface in C# terms
/// rather than mirroring it: managed-object construction, the snapshot reader
/// adapter, and the flat-to-discriminated event translation. Everything that is
/// a direct image of the C ABI is generated in <c>Generated/Input.g.cs</c>.
/// </summary>
public sealed unsafe partial class Input : IInput
{
    /// <summary>Creates an input system logging through a managed logger.</summary>
    public Input(INativeLogger? logger)
        : this(logger is null ? null : logger.Native) { }

    /// <inheritdoc/>
    public IInputReader CaptureSnapshot() => new SnapshotReader(GetSnapshot());

    /// <inheritdoc/>
    public int DrainEvents(Span<InputEvent> buffer)
    {
        if (buffer.IsEmpty) return 0;

        Span<ke_input_event> native = stackalloc ke_input_event[buffer.Length];
        int count = (int)DrainEventsRaw(native);

        for (int i = 0; i < count; i++)
        {
            ref readonly var n = ref native[i];
            ref var dst = ref buffer[i];
            dst = default;
            dst.Kind = (InputEventKind)n.kind;
            switch (dst.Kind)
            {
                case InputEventKind.KeyDown:
                case InputEventKind.KeyUp:
                    dst.Key = (Key)n.code;
                    break;
                case InputEventKind.MouseButtonDown:
                case InputEventKind.MouseButtonUp:
                    dst.Button = (MouseButton)n.code;
                    break;
                case InputEventKind.MouseScroll:
                    dst.Scroll = new Vector2(n.x, n.y);
                    break;
            }
        }
        return count;
    }

    /// <summary>Adapts a captured snapshot to the reader interface the sim tick consumes.</summary>
    private sealed class SnapshotReader : IInputReader
    {
        private readonly ke_input_snapshot _data;

        public SnapshotReader(ke_input_snapshot data) => _data = data;

        public bool IsKeyDown(Key key) => InputSnapshot.IsKeyDown(_data, key);
        public bool IsMouseButtonDown(MouseButton button) => InputSnapshot.IsMouseButtonDown(_data, button);

        public Vector2 MousePosition => new(_data.mouse_x, _data.mouse_y);
        public Vector2 MouseDelta => new(_data.mouse_dx, _data.mouse_dy);
        public Vector2 ScrollDelta => new(_data.scroll_dx, _data.scroll_dy);
    }
}
