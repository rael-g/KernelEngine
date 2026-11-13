using System.Numerics;

using global::KernelEngine.Job;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Job.Native;

public unsafe partial struct ke_job_system_handle
{
    public ke_job_system* @ref;

    [NativeTypeName("void (*)(ke_job_system *)")]
    public delegate* unmanaged[Cdecl]<ke_job_system*, void> destroy;
}
