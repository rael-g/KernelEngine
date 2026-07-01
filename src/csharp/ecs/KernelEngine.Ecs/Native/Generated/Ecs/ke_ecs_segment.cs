using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs_segment
{
    [NativeTypeName("const ke_entity *")]
    public ulong* entities;

    [NativeTypeName("void *[8]")]
    public _columns_e__FixedBuffer columns;

    [NativeTypeName("size_t")]
    public nuint count;

    public unsafe partial struct _columns_e__FixedBuffer
    {
        public void* e0;
        public void* e1;
        public void* e2;
        public void* e3;
        public void* e4;
        public void* e5;
        public void* e6;
        public void* e7;

        public ref void* this[int index]
        {
            get
            {
                fixed (void** pThis = &e0)
                {
                    return ref pThis[index];
                }
            }
        }
    }
}
