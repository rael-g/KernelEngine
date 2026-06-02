// Framework's native bindings (under Native/Generated/Framework/) reference
// kernel-level C types — ke_result, ke_allocator, ke_variant — which were
// emitted into KernelEngine.Kernel.Native by the Kernel.rsp generator pass.
// Pull that namespace in globally so generated framework bindings compile
// without ClangSharp having to inject a per-file using directive.
global using KernelEngine.Kernel.Native;
