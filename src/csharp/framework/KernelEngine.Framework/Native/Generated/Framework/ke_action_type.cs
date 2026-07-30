using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

[NativeTypeName("unsigned int")]
public enum ke_action_type : uint
{
    KE_ACTION_TYPE_BUTTON = 0,
    KE_ACTION_TYPE_AXIS1D = 1,
    KE_ACTION_TYPE_AXIS2D = 2,
    KE_ACTION_TYPE_AXIS3D = 3,
}
