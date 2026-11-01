using System.Numerics;
using System.Runtime.InteropServices;

using Xunit;

namespace EngineTests;

public unsafe class InputDrainTests
{

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static uint MockDrainEvents(ke_input* self, InputEvent* buffer, uint capacity)
    {
        if (capacity < 5) return 0;

        buffer[0].Kind = InputEventKind.KeyDown;
        buffer[0].Key = Key.W;

        buffer[1].Kind = InputEventKind.MouseScroll;
        buffer[1].Scroll = new System.Numerics.Vector2(1.5f, -2.5f);

        buffer[2].Kind = InputEventKind.KeyUp;
        buffer[2].Key = Key.Escape;

        buffer[3].Kind = InputEventKind.MouseButtonDown;
        buffer[3].Button = MouseButton.Left;

        buffer[4].Kind = InputEventKind.MouseButtonUp;
        buffer[4].Button = MouseButton.Right;

        return 5;
    }

    [Fact]
    public void DrainEvents_TranslatesNativeToManaged()
    {
        var mock = (ke_input*)NativeMemory.AllocZeroed((nuint)sizeof(ke_input));
        mock->drain_events = &MockDrainEvents; var input = new Input();

        var field = typeof(Input).GetField("_native", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        var oldNativeValue = field!.GetValue(input)!;
        field.SetValue(input, System.Reflection.Pointer.Box(mock, typeof(ke_input*)));

        var buffer = new InputEvent[10];
        var count = (int)input.DrainEvents(buffer);

        Assert.Equal(5, count);
        Assert.Equal(InputEventKind.KeyDown, buffer[0].Kind);
        Assert.Equal(InputEventKind.MouseScroll, buffer[1].Kind);
        Assert.Equal(InputEventKind.KeyUp, buffer[2].Kind);
        Assert.Equal(Key.Escape, buffer[2].Key);
        Assert.Equal(InputEventKind.MouseButtonDown, buffer[3].Kind);
        Assert.Equal(MouseButton.Left, buffer[3].Button);
        Assert.Equal(InputEventKind.MouseButtonUp, buffer[4].Kind);
        Assert.Equal(MouseButton.Right, buffer[4].Button);

        field.SetValue(input, oldNativeValue);
        NativeMemory.Free(mock);
    }

    [Fact]
    public void SnapshotAccessors_DecodeBitsets()
    {
        var data = new InputSnapshot();
        data.KeysDown[1] = 1UL << (65 % 64);
        data.MouseButtonsDown = 1u << (int)MouseButton.Right;

        using var input = new Input();

        Assert.True(input.SnapshotIsKeyDown(data, Key.A));
        Assert.False(input.SnapshotIsKeyDown(data, (Key)64));
        Assert.False(input.SnapshotIsKeyPressed(data, Key.A));
        Assert.True(input.SnapshotIsMouseButtonDown(data, MouseButton.Right));
        Assert.False(input.SnapshotIsMouseButtonDown(data, MouseButton.Left));
    }
}
