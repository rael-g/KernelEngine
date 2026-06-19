namespace KernelEngine.Kernel.Native;

public partial struct ke_input_event
{
    public ke_input_event_kind kind;

    [NativeTypeName("int32_t")]
    public int code;

    public float x;

    public float y;
}
