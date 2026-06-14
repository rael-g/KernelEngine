using System.Text;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Pointer-level wrapper around <see cref="FlecsEcs"/>. Implements
/// <see cref="IEcsAdapter"/> so Toolkit can depend on the interface without
/// a direct reference to this assembly.
/// </summary>
internal sealed unsafe class EcsAdapter : IEcsAdapter
{
    private readonly ke_ecs* _ecs;

    public EcsAdapter(FlecsEcs ecs)
    {
        _ecs = ecs.Native;
    }

    internal EcsAdapter(ke_ecs* ptr)
    {
        _ecs = ptr;
    }

    public uint Register<T>(string name) where T : unmanaged
    {
        var bytes = Encoding.UTF8.GetBytes(name + "\0");
        fixed (byte* p = bytes)
            return _ecs->component_register(_ecs, (sbyte*)p, (nuint)sizeof(T));
    }

    public ulong CreateEntity() => _ecs->entity_create(_ecs);

    public void EntityDestroy(ulong entity) => _ecs->entity_destroy(_ecs, entity);

    public void Add<T>(ulong entity, uint cid, in T value) where T : unmanaged
    {
        T* p = (T*)_ecs->component_add(_ecs, entity, cid);
        if (p != null) *p = value;
    }

    public bool TryGet<T>(ulong entity, uint cid, out T value) where T : unmanaged
    {
        T* p = (T*)_ecs->component_get(_ecs, entity, cid);
        if (p == null) { value = default; return false; }
        value = *p;
        return true;
    }

    public void Query<T>(uint cid, QueryAction<T> action) where T : unmanaged
    {
        ulong* outEntities;
        void*  outData;
        nuint  outCount;
        _ecs->query(_ecs, cid, &outEntities, &outData, &outCount);

        if (outCount == 0 || outEntities == null) return;
        T* data = (T*)outData;
        for (nuint i = 0; i < outCount; i++)
            action(outEntities[i], ref data[i]);
    }
}
