namespace KernelEngine.Kernel.Native;

public partial struct ke_frame
{
    [NativeTypeName("uint64_t")]
    public ulong frame_index;

    public double delta_time;

    public double total_time;
}
