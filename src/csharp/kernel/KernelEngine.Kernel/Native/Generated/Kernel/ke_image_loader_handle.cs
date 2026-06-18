namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_image_loader_handle
{
    public ke_image_loader* @ref;

    [NativeTypeName("void (*)(ke_image_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_image_loader*, void> destroy;
}
