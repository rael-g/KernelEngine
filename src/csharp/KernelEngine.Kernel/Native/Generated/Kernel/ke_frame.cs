namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_frame
{
    [NativeTypeName("uint64_t")]
    public ulong frame_index;

    public double delta_time;

    public double total_time;

    [NativeTypeName("const ke_input_snapshot *")]
    public ke_input_snapshot* input;
}
