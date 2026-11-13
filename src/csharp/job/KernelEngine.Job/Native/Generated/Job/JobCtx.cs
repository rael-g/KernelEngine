using System.Numerics;

using global::KernelEngine.Job;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Job.Native;

public unsafe partial struct JobCtx
{
    [NativeTypeName("const ke_result *")]
    public KernelEngine.Result.Native.Result* DepResults;

    [NativeTypeName("uint32_t")]
    public uint DepCount;
}
