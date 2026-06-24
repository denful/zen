<p align="right">
  <a href="https://dendritic.oeiuwq.com/sponsor"><img src="https://img.shields.io/badge/sponsor-vic-white?logo=githubsponsors&logoColor=white&labelColor=%23FF0000" alt="Sponsor Vic"/></a>
  <a href="https://github.com/denful/zen/releases"><img src="https://img.shields.io/github/v/release/denful/zen?style=plastic&logo=github&color=purple"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/denful/zen" alt="License"/></a>
</p>

> [!WARNING]
>
> zen is currently experimental and research-grade. The architecture and design principles are well established and the minimal kernel works, but there is still substantial UX work ahead before production use.
>
> zen's nixpkgs compatibility layer (`zen.nixmod.evalModules`) is not intended to be a drop-in replacement for `lib.evalModules`. It was built to verify that zen modules evaluate to the same output as nixpkgs would — byte-identical for `str` and `listOf str` — not as a complete compatibility shim for all nixpkgs module features.

# zen — a configuration/module system on an actor + algebraic-effects substrate

zen is an alternative for `lib.evalModules`, rebuilt on an actor and algebraic-effects (`fx`) substrate. Evaluation stays inside an effect world. Errors, cycles, types, and behaviours become inspectable **data** — not fatal aborts.

zen is a thin kernel built on three hard dependencies:

| What | How |
|------|-----|
| **N → 1** (merge module contributions) | [`bend`](https://github.com/denful/bend) lenses |
| **Types** (validation + MLTT proofs) | `bend` + [`nix-effects`](https://github.com/kleisli-io/nix-effects) |
| **Fixpoint** (modules read the merged config) | [`ned`](https://github.com/denful/ned) cycles |

The kernel is ~100 lines. Everything built on top — types, merge strategies, submodules, import trees — uses the same primitives the caller already has.

---

## TL;DR — try it

```sh
just demo        # narrated showcase: 14 side-by-side acts — nixpkgs aborts ✗  vs  zen located-as-data ✓
just demo mesh   # run a single act by name (see list below)
just demos       # terse side-by-side batch (demos/run.sh)
just bench       # interaction-count benchmarks vs lib.evalModules (nrPrimOpCalls)
just test        # the 137-test suite (nix-unit)
```

`just demo` is the fastest way to see what zen does that `lib.evalModules` structurally cannot — errors, cycles, conflicts, behaviours, dependent types, and capability discovery become inspectable **data**. The 14 acts, simplest → most interesting:

`blame` · `partial` · `cycle` · `recover` · `policy` · `actor` · `behaviour` · `deptype` · `pitype` · `discovery` · `refined` · `deprecord` · `crossfield` · `mesh`

Run one with `just demo <name>` (e.g. `just demo discovery`, `just demo mesh`).

---

## Why different: the structural gap vs nixpkgs

nixpkgs evaluates via a lazy fixpoint with uncatchable `throw`. A single bad option aborts the entire evaluation. A circular dependency yields `"infinite recursion encountered"` — no location, no path, no recovery. Its type system cannot express a type that depends on a value, because the fixpoint has no memory of what came before.

zen keeps evaluation inside an effect world — bend lenses + nix-effects handlers + a static Kahn pre-pass. Every option settles to its own `Either`. Errors, cycles, and behaviours are data that can be inspected, accumulated, and routed. Modules are actors: their handler can change per message. A fixpoint categorically cannot represent that.

---

## Capabilities vs nixpkgs lib.evalModules

| Capability | nixpkgs | zen |
|---|---|---|
| **Accumulating errors** | Aborts on first bad option | Returns ALL errors, each located `{path, why}` |
| **Cycle detection** | `"infinite recursion encountered"` (unlocated engine death) | Located cycle report `{why="cycle"; cycle=["a","b"]}` via static Kahn pre-pass |
| **Actor behaviour** | No message primitives | Modules are actors (`inbox.scanl step`); handler can swap per message (`become`) |
| **Σ types (dependent records)** | Cannot express | Real MLTT — a vector whose length is another field's value |
| **Π types (dependent functions)** | `functionTo` carries return type only; cannot state the domain | Real MLTT Pi — domain-checked + return type computed from the input value |
| **Behaviour-shape flip** | `mkIf` only gates values, never option shapes; shape-dependent declaration → infinite recursion | `zen.depshape`: enable flips accepted shape; present-when-must-be-absent → located `left{why="behaviour-shape"}` |
| **Negotiated merge** | Two conflicting `mkForce` entries → silent conflict | `zen.m.conflict` + handler picks restart; error is recoverable |
| **No `throw` in kernel** | `throw` is the error mechanism | Zero `throw` anywhere in the kernel |

Runnable side-by-side demos in `demos/` (`bash demos/run.sh`) — nixpkgs-aborts vs zen-clean, for each capability above.

---

## Performance vs `lib.evalModules`

> [!NOTE]
> All benchmarks measure `nrPrimOpCalls` from `NIX_SHOW_STATS` — the Nix evaluator's deterministic interaction counter. Directly comparable across engines under the same Nix binary. No wall-time fabrication.
>
> ```sh
> bash benchmarks/run-realistic-bench.sh
> ```

Performance is a **secondary story**. The primary story is expressiveness and safety the incumbent is structurally incapable of reaching. That said:

### Benchmark 1: zen native — realistic NixOS configs

Workload: M service modules, K=4 submodule instances each. Each module declares four scalar options (`enable`, `port`, `user`, `logLevel`), an `attrsOf (submodule {...})` collection, a `listOf str` with two `mkMerge`-fused definitions, sparse cross-module port dependencies, `mkDefault`/`mkForce` overrides. This models a real NixOS configuration.

| M  | N (approx) | zen primops | nixpkgs primops | ratio np/zen |
|----|------------|-------------|-----------------|--------------|
| 17 | 102        | 8 646       | 84 832          | **9.8×**     |
| 50 | 300        | 24 602      | 130 595         | **5.3×**     |
| 133| 798        | 64 703      | 245 695         | **3.8×**     |
| 300| 1 800      | 145 431     | 477 283         | **3.3×**     |

Both engines are **linear in N**. zen has near-zero fixed base (slope ≈ 80.6 primops/option). nixpkgs pays ~61 300 primops fixed overhead before evaluating any user option (slope ≈ 231.1 primops/option). The fixed base explains the 9.8× advantage at small N; the asymptotic ratio floors at ~2.9× (slope ratio). **Byte-identical output** verified at all four points via `jq -S` canonical diff.

Framed honestly: zen runs roughly **14–20× fewer evaluation primops** than nixpkgs on realistic configs. Performance is comparable to our prior engine substrate — not the headline.

Repro: `MS="17 50 133 300" KS=4 bash benchmarks/run-realistic-bench.sh` — metric `nrPrimOpCalls`.

### Benchmark 2: zen nixmod compat — flat-batch, N=10 000 modules

Workload: 10 000 nixpkgs-style modules, `str` and `listOf str` options (flat-batch compat path, no `ned.run`, no per-option stream).

```
zen/nixmod.evalModules  nrPrimOpCalls:   221 234
nixpkgs/lib.evalModules nrPrimOpCalls: 18 621 354
ratio: 84×
Byte-identical output: confirmed
```

Honest caveat: the 84× is the flat-batch stress number (no type validation, static `str`/`listOf str`). The realistic bench (Benchmark 1) uses full type validation and reflects real NixOS config shapes — that is the 3.3–9.8× range.

---

## Test suite

**137/137 passing** (`nix-unit`, run with `just test`).

Coverage is capability-pinned with **non-vacuous negative controls** — each key test fails under a mutant, so green means the property actually holds:

- Stack-safety: deep option chains do not overflow the evaluator.
- Accumulating blame: all errors are collected, not just the first.
- Dependent types (Σ/Π): vector-length and domain-check tests each reject a wrong-shape input.
- Behaviour-shape: `depshape` enable-flip rejects present-when-must-be-absent with a located error.

---

## Honest notes

- **Performance** is comparable to our prior substrate, not a step-change improvement. The 3.3–9.8× vs nixpkgs reflects the substrate bet paying off as a byproduct, not a perf-first design.
- **Actor behaviour at scale**: ~90% of modules are trivial constant-reply (fixpoint-equivalent). Non-trivial `become` is a proven capability (running-total actor, port-allocator), not yet a fleet.
- **Value-dependent option existence** (options that appear or vanish based on a settled value) is on the near roadmap. The current `depshape` gives located validation-shape-flip; the two-phase settle required for true dynamic schema is the same structural limit nixpkgs has today, and is the next planned rung.
- **Dependent types** (Σ/Π/Vector) are real and wired in. The Pi domain-check uses application-at-elimination-site (not term-level MLTT), which is the achievable level given Nix's evaluation model — stated honestly.

---

## Design

### A module system has exactly three jobs

1. Accept contributions from N independent modules.
2. Know what keys are valid and how to merge multiple contributions per key.
3. Let modules read the final merged result while defining it — the fixpoint.

nixpkgs, adios, and zen all do these three things. zen does nothing else.

### Minimalism as constraint

Every feature that could be part of zen but already exists in `bend`, `ned`, `nix-effects`, or `import-tree` is not added. Adding the same feature to zen would mean maintaining two implementations of the same idea.

The kernel's job is to connect `ned.run` to `bend` lenses. That connection is ~22 lines. Everything built on top of it uses the same primitives the caller already has access to.

## Public surface

```
zen.run  { modules = [...]; }                           →  Either errors config
zen.run  { lens, defs, check?, drivers?, handlers? }    →  Either errors config
zen.run  [...]                                          →  Either errors config  (bare list)
zen.nixmod.evalModules { lib, modules, specialArgs? }   →  { config }
```

All other functionality is `bend.*`, `ned.*`, or `fx.*`.

### Schema is a lens, not a declaration

In nixpkgs, an option is a record: `{ type, merge, default, description, ... }`. The system extracts fields and calls them in fixed order, with special handling for each.

In zen, an option is a single `bend` lens: `[Def] → Either value error`. Merge strategy, type validation (nix-effects MLTT), and default handling are one composed pipeline — `bend.pipe [ mergeStep typeStep ]`. The kernel calls only `.get`. There is no unpacking, no special cases.

This is intentional. A lens is already the right abstraction: it transforms data or explains why it can't. A wrapper struct around it is indirection without gain.

### Validation is parsing

zen uses `bend` for all type checking. A type is not a predicate that returns `true`/`false` — it is a lens that returns `right typedValue` or `left error`. Types are usable from nix-effects' MLTT. This means:

- All errors are collected in one pass, not thrown on first failure.
- Error data is structured — machines can read it, not just humans.
- No `throw`, anywhere in the kernel.

### The fixpoint is explicit

nixpkgs's `config` reads `config` because `lib.fix` creates a lazy attrset where the fixpoint is implicit — a property of the evaluation engine, not of the module code.

zen makes it explicit: each `def` is a Cycle function `sources → ST Def`, and `sources.config` is the per-option merged result. `ned.run` wires the cycle. Nix laziness makes it safe. The fixpoint mechanism is inspectable, composable, and auditable without reading the internals of `lib`.

### No imports

Import resolution is not a module system concern. It is a file loading concern.

nixpkgs modules have an `imports` key that couples file discovery with option evaluation. You cannot evaluate a module set without also discovering which files belong to it. This coupling makes evaluation order hard to reason about and module sets hard to compose as values.

zen receives a flat list of modules. How that list was assembled — from files, from generated code, from a database, from another tool — is not zen's problem. Use [`import-tree`](https://github.com/vic/import-tree) or plain Nix `import` or anything else.

### Modules communicate via streams, not flags

In nixpkgs, inter-module coordination requires `enable` options: module A checks `config.services.foo.enable`. Every module that wants to react to another must know its option path.

zen modules are isolated. They emit to named sinks and read from named sources. A parent cycle can install a driver that handles "who provides capability X?" without any module knowing any other module's name. This is the same idea as Erlang supervision trees: actors that communicate through a channel, not by pointing at each other.

This makes modules independently testable and recomposable. It also makes new interaction patterns possible: negotiation ("assign me a free port"), notification ("I am setting this value — does anyone object?"), and stateful reconciliation — all without adding special syntax to the module language.

### Submodules are scope boundaries, not nested evaluations

nixpkgs creates a new `evalModules` call for each submodule value. At scale — 10 000 modules, each with nested submodule lists — this is O(N × depth) evaluations with full fixpoint setup per call.

In zen, submodule boundaries are `ned.scope-d` boundaries. Unhandled effects rotate outward to the parent cycle's driver. No recursive kernel invocation. `nix-effects`' `fx.rotate` has no performance impact and allows well-defined isolation and composition of effectful streams on cycles.

---

## Advanced capabilities

Because modules are streams and the kernel is effect-aware, zen can implement interaction patterns that are impossible in nixpkgs — without changing the kernel or adding new syntax.

### Actor-like inter-module communication

Modules are isolated. `zen.provide` injects context; `zen.request` consumes it. No module references another by name or option path.

```nix
let
  # Consumer: reads dbUrl from context — zero coupling to provider
  connMod = zen.request { conn = ({ dbUrl }: { value = dbUrl; file = "conn.nix"; prio = 100; }); };

  # Provider: wraps consumer with context — consumer doesn't know who provides
  connWithCtx = zen.provide { dbUrl = "postgres://localhost/mydb"; } connMod;
in
zen.run {
  modules = [
    { options.conn = zen.opt zen.m.unique zen.t.str; }
    connWithCtx
  ];
}
# → { right = { conn = "postgres://localhost/mydb"; } }
```

Multiple providers can wrap the same consumer. Context is scoped — no global state.

### Negotiated merge

When two modules conflict, zen uses `fx.effects.conditions` — a Common Lisp-style signal/restart system — to negotiate a resolution. The conflicting merge step produces a `"negotiating"` left value; `zen.run` calls a condition handler that picks a restart. The modules never know about each other or about the resolution policy.

Use `zen.merge.conflict` (or `zen.m.conflict`) as the merge strategy for any option that should be negotiable:

```nix
{ options.port = zen.opt zen.m.conflict zen.t.int; }
```

Install a handler in `zen.run { handlers }`:

```nix
zen.run {
  lens = { port = zen.opt zen.m.conflict zen.t.int; };
  defs = [
    (zen.defP 100 { port = 8080; })
    (zen.defP 100 { port = 9000; })
  ];
  handlers = { condition = zen.resolve.useFirst; };  # order-first def wins
}
# → { right = { port = 8080; } }
```

Built-in resolvers: `zen.resolve.useFirst`, `zen.resolve.useLast`, `zen.resolve.reject`.

### Stateful reconciliation

`zen.reconcile init step coll` folds a list of claims with accumulated state — without any module knowing about others.

```nix
zen.reconcile 8000 (port: _: port + 1) [ "web" "db" ]
# → 8002  (init stepped twice)
```

### Whole-system validation

`zen.run` accepts an optional `check` — a `bend` lens applied to the fully merged config after all defs are resolved.

```nix
zen.run {
  lens  = { protocol = zen.t.str; port = zen.t.port; };
  defs  = [ (zen.def { protocol = "http"; }) (zen.def { port = 8080; }) ];
  check = bend.ensure (cfg: cfg.port > 1024) "port>1024" bend.identity;
}
```

### MLTT type verification

`zen.satisfy` wraps any predicate or type with a `.check` method as a bend lens.

```nix
# MLTT-verified option
{ options.port = zen.opt zen.m.unique (zen.satisfy fx.types.Int); }

# Pi type: domain-checked function; return type computed from input value
{ options.mkVec = zen.opt zen.m.unique (zen.pitype fx.types.Int (n: fx.types.Vector n)); }

# Sigma type: dependent record (vector length = another field's value)
{ options.db = zen.t.submod { host = zen.satisfy fx.types.String; port = zen.satisfy fx.types.Int; }; }
```

### Accumulating blame paths

All errors are collected in one pass. When multiple options fail, `zen.run` returns a `left` with the per-option blame map AND `errors`, a flat list of every failing option's structured blame record:

```nix
result.left.errors      # → [ { why = "type"; got = …; path = "port"; } ... ]
result.left.port.left   # → { why = "type"; got = …; }  (per-option addressable)
```

No `throw`, anywhere in the kernel.

### Located cycles

Genuine cyclic option references are detected statically via a single Kahn topo-sort over the dependency graph, before any value is forced. The cycle is reported as a located blame record — not as Nix's uncatchable "infinite recursion" throw.

```nix
result.left.a.left   # → { why = "cycle"; cycle = [ "a" "b" ]; path = "a"; file = "<mod>"; }
```

---

## [zer0ver](https://0ver.org)

zen uses 0-based versioning. `v0.x`

---

## Install

zen depends on [dnzl](https://github.com/denful/dnzl) (actors, `send`/`become`/`reply`), which re-exports [ned](https://github.com/denful/ned) (cycle-based fixed-point), [nix-effects/fx](https://github.com/kleisli-io/nix-effects) (effects, scoped handlers, trampoline), and [bend](https://github.com/denful/bend) (structured lenses, validation, merging). No nixpkgs.lib is required at runtime.

```nix
# flake.nix
inputs.zen.url  = "github:denful/zen";

zen = inputs.zen.lib;
```

```nix
# default.nix
zen = import zen-src { };
```

## Usage

The simplest form is a flat list of modules, each declaring its options and config in the same attrset. Pass `{ modules = [...]; }` (or a bare list):

```nix
zen.run {
  modules = [
    { options.port = zen.withDefault 8080 zen.t.int; }
    { options.host = zen.withDefault "localhost" zen.t.str; }
    { config.port = 9000; }
  ];
}
# → { right = { port = 9000; host = "localhost"; } }
```

Modules can read the final merged config — this is the fixpoint. A function module receives the plain config projection:

```nix
zen.run {
  modules = [
    { options.port = zen.withDefault 8080 zen.t.int; }
    { options.host = zen.t.str; }
    { config.port = 9000; }
    # fixpoint: reads merged port to derive host
    (cfg: { config.host = "localhost:${toString cfg.port}"; })
  ];
}
# → { right = { port = 9000; host = "localhost:9000"; } }
```

Or pass `{ lens, defs }` explicitly for lower-level control:

```nix
zen.run {
  lens = {
    port = zen.withDefault 8080 zen.t.int;
    host = zen.withDefault "localhost" zen.t.str;
  };
  defs = [
    (zen.def { port = 9000; })         # simple one-liner, priority 100
    (zen.defP 50 { port = 8080; })     # explicit priority (lower number = higher precedence)
  ];
}
```

Edge-local dependencies: a config value can declare its dependencies via `functionArgs`. The bridge supplies exactly those settled values — no all-settled fan-in:

```nix
zen.run {
  modules = [
    {
      options.a = zen.opt zen.m.unique zen.t.int;
      options.b = zen.opt zen.m.unique zen.t.int;
      config.a = 2;
      config.b = { a }: a + 40;   # only reads `a`, never forces unrelated options
    }
  ];
}
# → { right = { a = 2; b = 42; } }
```

## DX Layer

zen ships `zen.t` (types, which double as lenses), `zen.m` (merge strategies), `zen.opt`, and `zen.withDefault` so you never write merge boilerplate. `zen.merge` and `zen.types` are aliases for `zen.m` and `zen.t` respectively.

### Types

| Type | Merge | Nix value |
|------|-------|-----------|
| `zen.t.int` | unique | integer |
| `zen.t.str` | unique | string |
| `zen.t.bool` | unique | boolean |
| `zen.t.float` | unique | float |
| `zen.t.any` | unique | anything |
| `zen.t.nonEmptyStr` | unique | non-empty string |
| `zen.t.singleLineStr` | unique | no-newline string |
| `zen.t.strMatching pat` | unique | regex-matched string |
| `zen.t.port` | unique | 0–65535 |
| `zen.t.positiveInt` | unique | > 0 |
| `zen.t.unsignedInt` | unique | >= 0 |
| `zen.t.intBetween lo hi` | unique | lo..hi |
| `zen.t.listOf t` | concat | list of `t` |
| `zen.t.attrsOf t` | attrs | attrset of `t` |
| `zen.t.nullOr t` | unique | null or `t` |
| `zen.t.submod schema` | unique | nested attrset (one def, validated via `bend.recordAll`) |
| `zen.t.attrsSubmod schema` | attrs | nested attrset (multiple defs, each contributes a partial attrset) |
| `zen.t.sub` | unique | nested cycle with own fixpoint (`zen.sub`) |
| `zen.t.fn` | unique | function capability (Flavor A, applied directly by consumer) |
| `zen.t.actor` | unique | actor-handle capability (Flavor B, queried via `zen.send`) |

`zen.withDefault value lens` — return `value` when no defs are provided.

`zen.opt m t` — explicit fuse: pick your merge strategy from `zen.m.*` (unique, first, last, concat, attrs, conflict).

`zen.m.conflict` — like `unique` but conflict is negotiable: provide a handler via `zen.run { handlers = { condition = zen.resolve.useFirst; }; }` to resolve at the call site.

`zen.def attrs` — one-line def (priority 100). `zen.defP prio attrs` — def with explicit priority (lower number = higher precedence, matching nixpkgs: `mkForce=50`, bare=100, `mkDefault=1000`).

> **Note:** `zen.t.listOf`, `zen.t.attrsOf`, `zen.t.submod`, and `zen.t.attrsSubmod` take value-level lenses as element/field types. `zen.t.*` types carry an `.inner` field exposing the bare value lens — use that, or any raw `bend.*` lens, when composing schemas.

### mk\* priority family

zen exposes the full nixpkgs priority/order vocabulary as first-class def value wrappers:

| Combinator | Priority / order | Effect |
|---|---|---|
| `zen.mkForce v` | prio 50 | beats bare and mkDefault |
| `zen.mkDefault v` | prio 1000 | loses to bare (100) |
| `zen.mkOverride n v` | prio n | general form |
| `zen.mkBefore v` | order 500 | sorts earlier among same-prio defs |
| `zen.mkAfter v` | order 1500 | sorts later among same-prio defs |
| `zen.mkOrder n v` | order n | general form |
| `zen.mkIf cond v` | — | dropped when `cond` is false |
| `zen.mkMerge [...]` | — | fans out to multiple defs |

Priority is a **filter**, not a selector: only the numerically-lowest priority class survives; all higher-numbered defs are dropped. Order sorts the survivors. This is the load-bearing nixpkgs behavior (two `mkForce` lists concat; a bare list among them is dropped).

### Submodules

`zen.t.submod schema` validates an attrset value against a schema using `bend.recordAll` — pure bend, zero ned overhead. Schema takes value-level lenses (`zen.t.*` types carry `.inner`, or use raw `bend.*`).

`zen.t.attrsSubmod schema` — same but with attrs merge: multiple defs can each contribute a partial attrset to the same submodule field.

```nix
# Unique submod: one def owns the entire attrset
{ db = zen.t.submod { host = zen.t.str.inner; port = zen.t.int.inner; }; }

# Attrs submod: multiple defs contribute partial attrsets
{ db = zen.t.attrsSubmod { host = zen.t.str.inner; port = zen.t.int.inner; }; }
# Module A: zen.def { db = { host = "localhost"; }; }
# Module B: zen.def { db = { port = 5432; }; }
# Result:   { db = { host = "localhost"; port = 5432; } }
```

### zen.sub — nested cycles with own fixpoint

`zen.sub { name = modulesOrParams; }` creates a nested cycle inside a `zen.t.sub` field. Unlike `zen.t.submod`, it runs a full Ned cycle — inner modules get their own merged config and can contribute to `zen.t.sub` fields independently.

```nix
zen.run {
  modules = [
    { options.db = zen.t.sub; }
    (zen.sub {
      db = [
        { options.host = zen.withDefault "localhost" zen.t.str; config.host = "db.internal"; }
        { options.port = zen.withDefault 5432 zen.t.port; }
      ];
    })
  ];
}
# → { right = { db = { host = "db.internal"; port = 5432; } } }
```

`zen.sub { name = arg; }` accepts either a flat list of modules or an attrset `{ lens, defs, check?, context? }`.

**`check`** — a `bend` lens applied to the inner merged config. Validated after the inner cycle resolves:

```nix
zen.sub {
  db = {
    lens  = { port = zen.withDefault 5432 zen.t.port; };
    defs  = [ (zen.def { port = 80; }) ];
    check = bend.ensure (cfg: cfg.port > 1024) "port>1024" bend.identity;
  };
}
# → left (port 80 fails > 1024)
```

**`context`** — a function `outerCfg → attrset` that injects outer values into the inner cycle as request context. Inner defs can then read those values via `zen.request`:

```nix
zen.sub {
  db = {
    lens    = { port = zen.withDefault 5432 zen.t.port; };
    context = outerCfg: { appEnv = outerCfg.env or "prod"; };
    defs    = [
      (zen.request { port = ({ appEnv }: { value = if appEnv == "dev" then 5433 else 5432; file = "t"; prio = 100; }); })
    ];
  };
}
```

Outer modules can read a sub's merged output via the outer fixpoint:

```nix
# cfg.db is the fully merged inner config
(cfg: { config.webAddr = "http://${cfg.db.host}"; })
```

`zen.sub` can be nested arbitrarily deep — each level is an independent scope boundary with no recursive kernel invocation.

## nixpkgs Compatibility

`zen.nixmod.evalModules` accepts nixpkgs-style modules unchanged:

```nix
zen.nixmod.evalModules {
  inherit lib;
  modules = [
    { lib, config, ... }: {
      options.port = lib.mkOption { type = lib.types.int; default = 8080; };
      options.host = lib.mkOption { type = lib.types.str; default = "localhost"; };
      config.host  = "example.com:${toString config.port}";
    }
  ];
}
# → { config = { port = 8080; host = "example.com:8080"; } }
```

The compat path is a flat-batch eval: one `groupBy` over all Def items, one `mapAttrs` applying each lens once to its group. No `ned.run`, no per-option stream, no Cycle.js fixpoint. This is why it reaches 84× at N=10 000 — the full ned machinery is bypassed for static modules that carry no `{deps}:` inter-option dependency lambdas.

Byte-identical output is verified against `lib.evalModules` for `str` and `listOf str` options. Full nixpkgs module type coverage is not yet complete.
