using KernelEngine.Common.Native;

namespace KernelEngine.Input.Native;

[NativeTypeName("unsigned int")]
public enum ke_input_action : uint
{
    KE_INPUT_ACTION_RELEASE = 0,
    KE_INPUT_ACTION_PRESS = 1,
}
