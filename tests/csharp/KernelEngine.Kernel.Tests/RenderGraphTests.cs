using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

/// <summary>
/// Smoke tests for the managed <see cref="RenderGraph"/> / <see cref="RenderPass"/> wrappers.
/// Uses a mock <c>ke_render_graph</c> vtable that captures the params passed to <c>add_pass</c>
/// — no real GPU is initialized, so these run on any thread.
/// </summary>
public unsafe class RenderGraphTests
{
    // ── Shared mock-call recording state (test-instance scoped, reset per test) ───────────
    private static int _addPassCalled;
    private static int _removePassCalled;
    private static int _compileCalled;
    private static int _lastReadsCount;
    private static int _lastWritesCount;
    private static ke_pass_type _lastPassType;
    private static string _lastPassName = "";
    private static string _lastReadName = "";
    private static delegate* unmanaged[Cdecl]<ke_render_pass_ctx*, void*, void> _lastRecord;
    private static void* _lastUser;

    public RenderGraphTests()
    {
        _addPassCalled = _removePassCalled = _compileCalled = 0;
        _lastReadsCount = _lastWritesCount = 0;
        _lastPassName = _lastReadName = "";
        _lastRecord = null;
        _lastUser = null;
    }

    // ── Mock vtable callbacks ─────────────────────────────────────────────────────────────

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result MockAddPass(ke_render_graph* self, ke_render_pass_params* p)
    {
        _addPassCalled++;
        _lastPassType   = p->type;
        _lastReadsCount = (int)p->reads_count;
        _lastWritesCount = (int)p->writes_count;
        _lastRecord = p->record;
        _lastUser   = p->user;
        _lastPassName = p->name != null ? new string(p->name) : "";
        _lastReadName = (p->reads != null && p->reads_count > 0 && p->reads[0].name != null)
            ? new string(p->reads[0].name) : "";
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result MockRemovePass(ke_render_graph* self, sbyte* name) { _removePassCalled++; return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result MockCompile(ke_render_graph* self) { _compileCalled++; return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void MockDestroy(ke_render_graph* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result MockDeclareResource(ke_render_graph* self, ke_resource_desc* d) => ke_result.KE_OK;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result MockImportTexture(ke_render_graph* self, sbyte* name, ke_texture_handle h) => ke_result.KE_OK;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result MockExecute(ke_render_graph* self, ke_frame_packet* pkt) => ke_result.KE_OK;

    private static ke_render_graph BuildMockGraph()
    {
        var g = default(ke_render_graph);
        g.handle           = (void*)1;
        g.destroy          = &MockDestroy;
        g.declare_resource = &MockDeclareResource;
        g.import_texture   = &MockImportTexture;
        g.add_pass         = &MockAddPass;
        g.remove_pass      = &MockRemovePass;
        g.compile          = &MockCompile;
        g.execute          = &MockExecute;
        return g;
    }

    // ── Tests ─────────────────────────────────────────────────────────────────────────────

    [Fact]
    public void AddPass_marshals_name_type_and_resource_lists_to_native()
    {
        var native = BuildMockGraph();
        var graph  = new RenderGraph(&native);
        var pass = new RenderPass("user.fxaa")
            .WithType(PassType.Fullscreen)
            .Reads("backbuffer_final")
            .Writes("screen_post_fxaa")
            .OnRecord(_ => { /* no-op */ });

        graph.AddPass(pass);

        Assert.Equal(1, _addPassCalled);
        Assert.Equal("user.fxaa", _lastPassName);
        Assert.Equal(ke_pass_type.KE_PASS_FULLSCREEN, _lastPassType);
        Assert.Equal(1, _lastReadsCount);
        Assert.Equal(1, _lastWritesCount);
        Assert.Equal("backbuffer_final", _lastReadName);
    }

    [Fact]
    public void RemovePass_disposes_and_drops_matching_wrapper()
    {
        var native = BuildMockGraph();
        var graph  = new RenderGraph(&native);
        var pass = new RenderPass("temp").OnRecord(_ => { });
        graph.AddPass(pass);

        Assert.True(graph.RemovePass("temp"));
        Assert.Equal(1, _removePassCalled);
        // Re-adding the same pass would fail if Dispose() hadn't released the prior GCHandle.
        var pass2 = new RenderPass("temp").OnRecord(_ => { });
        graph.AddPass(pass2);
        Assert.Equal(2, _addPassCalled);
    }

    [Fact]
    public void Recompile_calls_native_compile()
    {
        var native = BuildMockGraph();
        var graph  = new RenderGraph(&native);
        graph.Recompile();
        Assert.Equal(1, _compileCalled);
    }

    [Fact]
    public void Record_trampoline_dispatches_to_the_managed_delegate()
    {
        // Captures whether the user's lambda actually fires when the static trampoline
        // is invoked with the same `user` pointer add_pass received.
        var native = BuildMockGraph();
        var graph  = new RenderGraph(&native);
        bool delegateFired = false;
        var pass = new RenderPass("dispatch.test").OnRecord(_ => delegateFired = true);
        graph.AddPass(pass);

        Assert.NotEqual(IntPtr.Zero, (IntPtr)_lastRecord);
        Assert.NotEqual(IntPtr.Zero, (IntPtr)_lastUser);

        // The pass record callback expects a ke_render_pass_ctx*. Our mock ctx is a stack
        // value initialised to defaults — the trampoline only reads `user`, not anything off
        // ctx itself in this lambda, so a zeroed ctx is safe for the round-trip check.
        var ctx = default(ke_render_pass_ctx);
        _lastRecord(&ctx, _lastUser);

        Assert.True(delegateFired);
    }

    [Fact]
    public void AddPass_without_OnRecord_throws()
    {
        var native = BuildMockGraph();
        var graph  = new RenderGraph(&native);
        var pass = new RenderPass("missing.callback");
        Assert.Throws<InvalidOperationException>(() => graph.AddPass(pass));
    }
}
