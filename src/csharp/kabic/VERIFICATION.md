# Verifying kabic-generated code

kabic has no test suite of its own and no oracle beyond the C header. For a
domain that never had a hand-written wrapper, there is nothing to diff the
generated output against — this checklist is the substitute. Run it every
time a domain is migrated or a header changes.

## 1. Before generating

- [ ] Every `///` doc comment on a slot/param that needs a tag is `/** */`,
      not `///`. Triple-slash comments do not reliably attach to clang's
      structured-comment parser; block comments do.
- [ ] Every `const char *` parameter meant to cross the ABI as text has
      `[utf8]` on its `@param` line.
- [ ] Every `[out]` parameter is tagged, including ones that are also part of
      a pointer+count pair (`[out,array_of:count_name]`).
- [ ] A slot taking a bare C function pointer (not a `[callback]`-tagged
      vtable-by-value struct) has `[raw_callback]` on that parameter.
- [ ] A slot whose own RETURN is a bare C function pointer has
      `[raw_callback]` on the slot's own summary line (not a param — there is
      no param to put it on).
- [ ] A parameter whose type this consumer cannot reference (cross-domain
      pointer into a project the consuming assembly has no reference to) has
      `[opaque]`.
- [ ] A slot whose managed surface is going to collide by name with an
      existing hand-written member of a different shape (property vs.
      generated method, different return type) is decided in advance:
      either the hand-written member is renamed, or the slot gets `[idiom]`
      and stays fully hand-written.
- [ ] `[try]` is on any slot where a boolean return means found/not-found,
      not succeeded/failed.

## 2. Extraction (`kabic extract`, or `kabic generate --domain <name>`)

- [ ] Run twice with the exact same arguments; diff the two `ke_api.json`
      outputs. They must be byte-identical. A diff here means a path-identity
      bug in the extractor, not a header problem — do not proceed until this
      passes.
- [ ] If the header pulls in types from another domain purely for
      resolution (typedef aliases, enum recognition), those headers are
      passed via `--aux`, not as primary targets. Confirm the resulting
      `enums`/`structs`/`vtables` counts do NOT include anything from the aux
      headers — only `type_aliases` should reflect them.
- [ ] Every `@param` tag that was written actually appears on the parameter
      it was meant for in the output JSON (`grep` the param name and its
      `tags` array). A tag written on the wrong line, or that got merged into
      an adjacent comment block, silently attaches to nothing or to the wrong
      target.

## 3. Generated C# — read the whole file once, checking for these specific defects

Do not spot-check by pattern-matching the diff against a previous domain —
read every method body. The checklist below is exhaustive for defect classes
that have occurred; a defect outside this list is still possible.

- [ ] **No literal `struct` or `const` in any type position.** These must
      never appear in emitted C# (`ke_render_pass_ctx * X` instead of
      `ke_render_pass_ctx* X`, `const char * X` anywhere). If found, the type
      resolution path (`CsType`) has a normalization gap.
- [ ] **No unresolved bare ABI type name** (a C# identifier that isn't a
      primitive, isn't Pascal-cased, and has no matching binding anywhere in
      the consuming project). Build the project; every such name is a
      compile error, but confirm none of them were "fixed" by accident with
      an unrelated `using`.
- [ ] **Every `[out]` parameter that is a double pointer (`T **`) resolves to
      `T*` in the C# signature, not bare `T`.** A single `Deref` call must
      strip exactly one level. Check this explicitly for any slot whose out
      parameter type ends in `**`.
- [ ] **Every `ke_bool`-typed return or parameter is compared/cast with
      `!= 0` / `(byte)x`, never assigned directly to/from a C# `bool`.**
      `ke_bool` and the literal C keywords `bool`/`_Bool` are NOT the same
      thing to the binding generator underneath kabic — verify both are
      handled, not just one.
- [ ] **Every `[utf8]` parameter has its `Encoding.UTF8.GetBytes` +
      `fixed (byte* ... )` prologue actually present in the method body.**
      Check this per slot SHAPE (`Plain`, `ReturnsOutParam`, `TupleOutParams`,
      `Sequence`, `Fallible`, `Try`) — a shape that has never combined
      `[utf8]` with its own control flow before is where this goes missing.
- [ ] **Every slot with 2+ non-sequence `[out]` params AND other ordinary
      input params renders those inputs into the signature**, not just the
      tuple. Check both the C# signature and the native call argument order
      (native argument order follows original declaration order, not the
      reshaped public signature).
- [ ] **A slot returning a pointer, with a trailing error out-param, checks
      `result == null` for failure — not `err != null`.** A slot returning a
      non-pointer value with a trailing error out-param does the opposite
      (checks `err != null`, since there's no null-sentinel to check). Verify
      the right one was picked for each such slot.
- [ ] **A parameter typed as one of this domain's OWN enums renders as that
      enum type and casts back to the native enum at the call site** — not
      as a raw integer.
- [ ] **A parameter typed as a FOREIGN domain's enum (declared in an `--aux`
      header, or in a header not extracted at all) renders under its
      original ABI name**, unchanged, not Pascal-cased — it must match
      whatever name that other domain's own binding already uses.
- [ ] **`Dispose()` calls `OnDispose()` before releasing the native
      pointer.** If the idiom layer owns extra resources (another domain's
      handle, GCHandles pinning callback delegates), `OnDispose()` is
      implemented as a `partial void` in the idiom file — confirm it is,
      and that nothing there duplicates work the generated `Dispose` also
      does.
- [ ] **No C# reserved word appears unescaped as an identifier**
      (`out`, `params`, `ref`, `event`, `fixed`, `is`, ... — the full list is
      in `Idioms.CsKeywords`). A parameter or field named after one must come
      through as `@name`.
- [ ] **A slot whose Pascal-cased name already starts with the shape's own
      prefix is not double-prefixed** (`Try` shape on a slot already named
      `try_get_x` must not render `TryTryGetX`).

## 4. Cross-domain wiring

- [ ] Every cross-domain pointer type actually resolves: the consuming
      project has a `using` (via `--using`) for whichever namespace defines
      it, OR the parameter is `[opaque]` and renders as `void*`.
- [ ] If `[opaque]` was used, confirm this consumer genuinely has no project
      reference to the type's real owner — `[opaque]` is not a shortcut
      around adding a legitimate `--using`.
- [ ] `Convention.TypeNameOverrides` additions are justified by one of:
      (a) the derived name collides with the containing namespace, or
      (b) preserving a pre-existing public name with call sites, not
      introduced for cosmetic preference alone.

## 5. Regenerate everything, not just the domain that changed

Any change to `Kabic.Core` or `Kabic.CSharpBackend` can affect every
previously migrated domain, not just the one being worked on.

```bash
dotnet run --project src/csharp/kabic/Kabic.Cli -- generate
```

- [ ] `git status` shows no unexpected diffs in domains other than the one
      being changed. Any diff there means the change had a broader effect —
      read it before deciding it's safe.
- [ ] Clear `~/.local/share/dotnet/runfile/{check_api_drift,regenerate_api}-*`
      before any of the above if a kabic source file changed. The file-based
      `dotnet run` cache does not reliably invalidate on `#:project`-referenced
      file changes.

## 6. Full verification

Run in this order; do not skip any step because an earlier one passed:

1. `dotnet build KernelEngine.slnx` — zero errors.
2. `dotnet test KernelEngine.slnx` — all pass, count matches or exceeds the
   prior run (a silently-dropped test file is not a passing run).
3. `dotnet run scripts/verify.cs -- gates` — every `check_*.cs`, `kabic check drift` included, green.
4. `zig build --prefix build/native --cache-dir build/zig-cache` — zero errors.
5. If the domain has any live usage in an example or test that exercises the
   changed slot at runtime (not just at compile time), run it. A shape can
   compile correctly and still marshal the wrong bytes.

## 7. What NOT to trust

- A clean build is necessary, not sufficient — pointer-typed parameters can
  compile against the wrong type and still produce wrong behavior at
  runtime (e.g. an `[opaque]` mismatch that happens to also compile as some
  other pointer type).
- A previous domain's generated file being byte-identical after a kabic
  change is evidence the change didn't affect THAT shape — it says nothing
  about a shape combination that domain never exercised.
- The tag vocabulary (the tags `Kabic.Frontend` recognises) is not
  closed. A new domain can need a new tag. If a slot's meaning cannot be
  expressed with the existing vocabulary, add a tag — do not force an
  existing tag to mean something it wasn't defined to mean.
