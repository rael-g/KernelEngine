using System.Numerics;

using KernelEngine.Common.Native;
using KernelEngine.Input.Native;

namespace KernelEngine.Input;

/// <summary>
/// The input service over <c>ke_input</c>, with a snapshot reader and the translation of native
/// events into <see cref="InputEvent"/> values.
/// </summary>
public sealed unsafe partial class Input : IInput
{
    /// <inheritdoc/>
    public IInputReader CaptureSnapshot() => new SnapshotReader(this, GetSnapshot());

    /// <summary>An <see cref="IInputReader"/> over one captured native snapshot; it never changes
    /// after capture.</summary>
    private sealed class SnapshotReader : IInputReader, INativeInputReader
    {
        private readonly Input _owner;
        private InputSnapshot _data;

        public SnapshotReader(Input owner, InputSnapshot data)
        {
            _owner = owner;
            _data = data;
        }

        public bool IsKeyDown(Key key)
        {
            return _owner.SnapshotIsKeyDown(_data, key);
        }

        public bool IsKeyPressed(Key key)
        {
            return _owner.SnapshotIsKeyPressed(_data, key);
        }

        public bool IsKeyReleased(Key key)
        {
            return _owner.SnapshotIsKeyReleased(_data, key);
        }

        public bool IsMouseButtonDown(MouseButton button)
        {
            return _owner.SnapshotIsMouseButtonDown(_data, button);
        }

        public Vector2 MousePosition => new(_data.MouseX, _data.MouseY);
        public Vector2 MouseDelta => new(_data.MouseDx, _data.MouseDy);
        public Vector2 ScrollDelta => new(_data.ScrollDx, _data.ScrollDy);

        InputSnapshot INativeInputReader.Native => _data;
    }
}
