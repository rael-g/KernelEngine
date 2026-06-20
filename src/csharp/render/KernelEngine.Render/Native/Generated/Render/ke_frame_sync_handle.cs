using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_frame_sync_handle
{
    public ke_frame_sync* @ref;

    [NativeTypeName("void (*)(ke_frame_sync *)")]
    public delegate* unmanaged[Cdecl]<ke_frame_sync*, void> destroy;
}
