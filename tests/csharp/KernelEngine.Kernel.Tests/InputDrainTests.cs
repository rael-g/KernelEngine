using System.Numerics;
using System.Runtime.InteropServices;
using Xunit;

namespace EngineTests;

public unsafe class InputDrainTests
{
    public InputDrainTests() { KernelThread.SetCurrentName("ke.main"); }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static uint MockDrainEvents(ke_input* self, ke_input_event* buffer, uint capacity)
    {
        if (capacity < 5) return 0;
        
        buffer[0].kind = ke_input_event_kind.KE_INPUT_EVENT_KEY_DOWN;
        buffer[0].code = (int)Key.W;
        
        buffer[1].kind = ke_input_event_kind.KE_INPUT_EVENT_MOUSE_SCROLL;
        buffer[1].x = 1.5f;
        buffer[1].y = -2.5f;

        buffer[2].kind = ke_input_event_kind.KE_INPUT_EVENT_KEY_UP;
        buffer[2].code = (int)Key.Escape;

        buffer[3].kind = ke_input_event_kind.KE_INPUT_EVENT_MOUSE_BUTTON_DOWN;
        buffer[3].code = (int)MouseButton.Left;

        buffer[4].kind = ke_input_event_kind.KE_INPUT_EVENT_MOUSE_BUTTON_UP;
        buffer[4].code = (int)MouseButton.Right;
        
        return 5;
    }

    [Fact]
    public void DrainEvents_TranslatesNativeToManaged()
    {
        var mock = (ke_input*)NativeMemory.AllocZeroed((nuint)sizeof(ke_input));
        mock->drain_events = &MockDrainEvents;        var input = new Input(null);
        
        // Use reflection to swap _native for our mock
        var field = typeof(Input).GetField("_native", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        var oldNativeValue = field!.GetValue(input)!;
        field.SetValue(input, System.Reflection.Pointer.Box(mock, typeof(ke_input*)));

        var buffer = new InputEvent[10];
        int count = input.DrainEvents(buffer);

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
    public void SnapshotReader_CorrectlyReadsBits()
    {
        var data = new ke_input_snapshot();
        // Key 65 (A) -> word 1, bit 1
        data.keys_down[1] = 1UL << (65 % 64);
        data.mouse_x = 100;
        data.mouse_y = 200;
        data.mouse_buttons_down = 1u << (int)MouseButton.Right;

        var reader = new InputSnapshotReader(data);

        Assert.True(reader.IsKeyDown(65));
        Assert.False(reader.IsKeyDown(64));
        Assert.Equal(100, reader.MousePosition.X);
        Assert.True(reader.IsMouseButtonDown((int)MouseButton.Right));
    }
}
