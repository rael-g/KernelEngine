# kabic's second backend — what generating Zig proved, and what it did not

kabic exists so that adding a module costs one header and adding a language costs one backend,
never `modules × languages`. The C# backend was written first, against an ecosystem of
hand-written C# that already existed, and that order is the risk: every idiom form was
discovered by looking at C# and asking *"what would have generated this?"* A form that reads as
natural only because C# has classes, properties, `ReadOnlySpan<T>`, `GCHandle` and generics
would be indistinguishable, from the inside, from a genuinely language-neutral one.

So a second backend was built to answer one question: **is kabic a generator, or a C# generator
wearing a generator's clothes?**

Zig is the probe because it shares almost nothing ergonomically with C# — no classes, no
properties, no inheritance, no GC, no exceptions — and because it is the engine's own
implementation language, so a generated Zig surface has a real consumer.

The trap, stated up front because it is the cheap wrong answer: Zig imports C headers natively,
so emitting the header 1:1 looks like a complete backend and is not one. It reproduces exactly
the experience a binding exists to prevent — an author passing `*ke_error` out-parameters,
checking `bool`, spelling `[*c]const u8`, and computing pointer-plus-count pairs by hand. **A
Zig backend that is a re-export of the C header is a failed backend, not a cheap one.** The
backend is cheaper than C# in machinery, not in design.

---

## The answer

**kabic is a generator.** Across every description in `scripts/api_domains.json`, **no header was
edited to make Zig work**, and no tag turned out to be meaningless outside C#. A backend far
smaller than the C# one produces Zig that the Zig compiler accepts and a Zig author can read: a
consumer compiled against the generated module iterates a slice, unwraps an optional, uses `try`,
and switches on an error set, with no `[*c]`, no C type name, no out-parameter and no
pointer-plus-count pair anywhere in it.

Nothing imports the header. The ABI is declared in Zig from the description, which is what lets
each pointer say whether it is nullable and whether it reaches one value or many — the two things
a C import collapses into `[*c]`.

### The sharpest result runs the other way

The second ruler found defects in the first one's output, not the reverse.

- **Fifteen written-back parameters carried no `[out]`.** In C# they had been projecting as raw
  pointers through a public managed API — including a raw native struct pointer — which is the
  exact thing a binding exists to have stopped. C# compiled them and they read as plausible. The
  same declarations came out of Zig as an optional of nothing, visibly nonsense at a glance.
  `scripts/check_out_params.cs` now refuses an `out_`-prefixed parameter that carries no `[out]`.
- **Tagging them exposed a second defect the pointers had masked.** A slot with a `ke_bool` return
  and three written-back parameters classified as a tuple and its **failure lane disappeared**,
  returning uninitialised stack values for a resource that was never uploaded. The header declares
  `[try]` now, so a render pass can skip a draw instead of binding garbage.
- **The mirror-image defect existed in the Zig backend**: a `ke_bool` return was read as the
  failure lane whether the slot had one or not, so a predicate projected as returning nothing and
  threw its answer away. A bool return is the failure lane only when the slot is fallible or
  `[try]`.

Both are the same class — a value silently dropped by a generator, caught only because a second
generator disagreed. That is what a second backend buys, and it paid for itself on its first run.

## Two tags that looked like leaks and are not

These were the leading suspects for "the description is C#-shaped", and both cleared.

**`[rooted]`** is defined in terms of a GC that Zig does not have. But what the header *declares*
is "an opaque pointer the native side stores and never dereferences", which is language-neutral;
the GC is only what C# must do to honour that. C# gets a handle table, Zig gets a pointer it
already owns. The divergence is correct. The name is C#-flavoured; the information is not.

**`[interface]`** renders to a C# construct with no Zig counterpart. The Zig backend never reads
the tag — it projects the concrete struct. Also correct rather than a gap: the tag exists so a
caller can depend on a capability without dragging the native call along, and Zig expresses that
by taking the struct, or by taking `anytype` and letting comptime check it.

## What the divergences actually were

Every one of them is either a form the backend has not rendered yet, or description that was
lossy for both languages. None required a header to change shape for one language.

**Lossy description, fixed.** A slot's receiver type was dropped entirely: the frontend strips
parameter 0 as "the struct this slot hangs off", which is true for a vtable and false for an
owner-handle wrapper, whose `destroy` was therefore described with zero parameters. The Zig
backend had to recover it from the `_handle` naming convention — a guess that compiles either way,
which is the worst kind. C# never noticed because it gets handle structs from ClangSharp: **a
second generator was covering for a hole in the first one's description.** `ApiSlot.Receiver`
carries it now.

**Per-language plumbing the description should not carry.** A composed foreign type is named but
never declared. C# solves it with a namespace `using`, which works only because a C# namespace
exists independently of the generator; Zig needs an `@import` per foreign domain, and therefore a
domain-to-module map. `scripts/api_domains.json` is the right place for it.

**Naming policy, backend-side.** Zig forbids shadowing an outer declaration, and a vtable with a
slot and a parameter of the same name hits it. `type` is a keyword, so part of one domain reads
`@"type"` — valid and ugly; the C# backend hit the mirror case and answered with escaping too, so
escaping is the precedent, but a rename would read better.

**Forms, not conflicts.** The domains the backend refused all refused for the same reason: a form
C# has received and Zig has not. Notably Zig's answer to several is the *cheaper* one — a callback
is a function pointer plus an opaque context, with no delegate, no trampoline and no handle table.

## The caveat that matters most

**The Zig backend is wired into no build.** `scripts/generate_zig.cs` has no caller anywhere in
the tree; `scripts/api_domains.json` declares no Zig output directory; no generated Zig is
versioned. The only thing that exercises the backend is `scripts/check_zig_shapes.cs`, against
fixtures, into a temporary directory.

So the shapes it declares are green, and that green measures **the backend**, not the product. A
tag change in a C header cannot break Zig output today, because no Zig output exists to break. The
conclusion above — that kabic is a generator — is earned on the evidence described here and
remains true; what is *not* established is that it stays true unattended. Until a domain's Zig
module is generated into the tree and compiled by `build.zig`, the second ruler is something run
by hand, and a ruler run by hand drifts.

That is the first piece of work for whoever picks this up, ahead of any remaining form.

## Remaining work

| work | sessions |
|---|---|
| generate a domain's Zig module into the tree and compile it from `build.zig` | 1 |
| domain-to-module import map, plus the shadowing and keyword policy | 1 |
| fixed-size array fields and enum members whose initialiser names a sibling | ~0.5 |
| the forms Zig has not received | rides the C# arc; each lands with the form it mirrors |

The last row is the point of the whole exercise: a form is not finished when one language can
read it.
