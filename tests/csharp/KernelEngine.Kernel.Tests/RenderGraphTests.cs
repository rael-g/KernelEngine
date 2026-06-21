using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Reflection;
using Xunit;

namespace EngineTests;

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
    private static bool MockAddPass(ke_render_graph* self, ke_render_pass_params* p, ke_error** out_error)
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
        return true;
    }

    [Fact]
    public void RemovePass_returns_false_for_empty_name()
    {
        var native = BuildMockGraph();
        var graph  = new RenderGraph(&native);
        Assert.False(graph.RemovePass(""));
    }

    [Fact]
    public void RemovePass_returns_false_when_not_found()
    {
        var native = BuildMockGraph();
        g_mockRemovePassResult = false;
        var graph  = new RenderGraph(&native);
        try {
            Assert.False(graph.RemovePass("unknown"));
        } finally { g_mockRemovePassResult = true; }
    }

    private static bool g_mockRemovePassResult = true;
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockRemovePass(ke_render_graph* self, sbyte* name, ke_error** out_error)
    {
        _removePassCalled++;
        return g_mockRemovePassResult;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockCompile(ke_render_graph* self, ke_error** out_error) { _compileCalled++; return true; }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void MockDestroy(ke_render_graph* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockDeclareResource(ke_render_graph* self, ke_resource_desc* d, ke_error** out_error) => true;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockImportTexture(ke_render_graph* self, sbyte* name, ke_texture_handle h, ke_error** out_error) => true;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool MockExecute(ke_render_graph* self, ke_frame_packet* pkt, ke_error** out_error) => true;

    private static ke_render_graph BuildMockGraph()
    {
        var g = default(ke_render_graph);
        g.handle           = (void*)1;
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
    public void AddPass_CallsNativeAddPass()
    {
        var native = BuildMockGraph();
        var graph = new RenderGraph(&native);
        var pass = new RenderPass("test").OnRecord(_ => { });

        graph.AddPass(pass);

        Assert.Equal(1, _addPassCalled);
    }

    [Fact]
    public void AddPass_MarshalsNameCorrectly()
    {
        var native = BuildMockGraph();
        var graph = new RenderGraph(&native);
        var pass = new RenderPass("user.fxaa").OnRecord(_ => { });

        graph.AddPass(pass);

        Assert.Equal("user.fxaa", _lastPassName);
    }

    [Fact]
    public void AddPass_MarshalsTypeCorrectly()
    {
        var native = BuildMockGraph();
        var graph = new RenderGraph(&native);
        var pass = new RenderPass("test")
            .WithType(PassType.Fullscreen)
            .OnRecord(_ => { });

        graph.AddPass(pass);

        Assert.Equal(ke_pass_type.KE_PASS_FULLSCREEN, _lastPassType);
    }

    [Fact]
    public void AddPass_MarshalsReadsCountCorrectly()
    {
        var native = BuildMockGraph();
        var graph = new RenderGraph(&native);
        var pass = new RenderPass("test")
            .Reads("r1")
            .Reads("r2")
            .OnRecord(_ => { });

        graph.AddPass(pass);

        Assert.Equal(2, _lastReadsCount);
    }

    [Fact]
    public void AddPass_MarshalsWritesCountCorrectly()
    {
        var native = BuildMockGraph();
        var graph = new RenderGraph(&native);
        var pass = new RenderPass("test")
            .Writes("w1")
            .OnRecord(_ => { });

        graph.AddPass(pass);

        Assert.Equal(1, _lastWritesCount);
    }

    [Fact]
    public void AddPass_MarshalsResourceNameCorrectly()
    {
        var native = BuildMockGraph();
        var graph = new RenderGraph(&native);
        var pass = new RenderPass("test")
            .Reads("backbuffer_final")
            .OnRecord(_ => { });

        graph.AddPass(pass);

        Assert.Equal("backbuffer_final", _lastReadName);
    }

    [Fact]
    public void RemovePass_ReturnsTrue_WhenSuccessful()
    {
        var native = BuildMockGraph();
        var graph = new RenderGraph(&native);
        var pass = new RenderPass("temp").OnRecord(_ => { });
        graph.AddPass(pass);

        Assert.True(graph.RemovePass("temp"));
    }

    [Fact]
    public void RemovePass_CallsNativeRemovePass()
    {
        var native = BuildMockGraph();
        var graph = new RenderGraph(&native);
        var pass = new RenderPass("temp").OnRecord(_ => { });
        graph.AddPass(pass);

        graph.RemovePass("temp");

        Assert.Equal(1, _removePassCalled);
    }

    [Fact]
    public void RemovePass_AllowsReaddingPassWithSameName()
    {
        var native = BuildMockGraph();
        var graph = new RenderGraph(&native);
        var pass = new RenderPass("temp").OnRecord(_ => { });
        graph.AddPass(pass);
        graph.RemovePass("temp");

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
    public void RenderPass_constructor_throws_on_invalid_name()
    {
        Assert.Throws<ArgumentException>(() => new RenderPass(""));
        Assert.Throws<ArgumentException>(() => new RenderPass(null!));
    }

    [Fact]
    public void BuildNativeParams_throws_if_already_attached()
    {
        var pass = new RenderPass("test").OnRecord(_ => { });
        pass.BuildNativeParams(out _);
        Assert.Throws<InvalidOperationException>(() => pass.BuildNativeParams(out _));
        pass.Dispose();
    }

    [Fact]
    public void RecordTrampoline_swallows_exception()
    {
        var native = BuildMockGraph();
        var graph  = new RenderGraph(&native);
        var pass = new RenderPass("error.test").OnRecord(_ => throw new Exception("boom"));
        graph.AddPass(pass);

        var ctx = default(ke_render_pass_ctx);
        // Should not throw
        _lastRecord(&ctx, _lastUser);
    }

    [Fact]
    public void RecordTrampoline_returns_on_null_user()
    {
        // Calling it via reflection since it's private static
        var method = typeof(RenderPass).GetMethod("RecordTrampoline", BindingFlags.NonPublic | BindingFlags.Static);
        // It has UnmanagedCallersOnly, but maybe I can Invoke it if I pass valid pointers?
        // No, Invoke always fails on UnmanagedCallersOnly.
        // But I can get the function pointer from the BuildNativeParams!
        
        var pass = new RenderPass("test").OnRecord(_ => { });
        pass.BuildNativeParams(out var p);
        
        var record = (delegate* unmanaged[Cdecl]<ke_render_pass_ctx*, void*, void>)p.record;
        record(null, null); // Should return immediately
        pass.Dispose();
    }
}
