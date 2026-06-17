namespace KernelEngine.Kernel.Native;

public partial struct ke_ndc_convention
{
    [NativeTypeName("ke_bool")]
    public byte z_zero_to_one;

    [NativeTypeName("ke_bool")]
    public byte y_flip;

    [NativeTypeName("ke_bool")]
    public byte left_handed;
}
