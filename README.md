<p align="right">
  <a href="https://dendritic.oeiuwq.com/sponsor"><img src="https://img.shields.io/badge/sponsor-vic-white?logo=githubsponsors&logoColor=white&labelColor=%23FF0000" alt="Sponsor Vic"/></a>
  <a href="https://deepwiki.com/denful/zen"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
  <a href="https://github.com/denful/zen/releases"><img src="https://img.shields.io/github/v/release/denful/zen?style=plastic&logo=github&color=purple"/></a>
  <a href="https://dendritic.oeiuwq.com"><img src="https://img.shields.io/badge/Dendritic-Nix-informational?logo=nixos&logoColor=white" alt="Dendritic Nix"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/denful/zen" alt="License"/></a>
</p>



> [!WARNING]
> 
> Zen is currently experimental, while the architecture and design principles are well stablished and the minimal kernel works, we still have a lot to work on UX for it to actually be used.
> 
> Zen's nixpkgs compatibility layer is currenty not intended to be a drop-in replacement for lib.evalModules, it was made as way to ensure that zen modules evaluate to the same output as nixpkgs would do.

# **Zen**. A minimal stream-based Nix module system.

Zen is a thin kernel built on three hard dependencies:

| What | How |
|------|-----|
| **N → 1** (merge module contributions) | [`bend`](https://github.com/denful/bend) lenses |
| **Types** (validation + MLTT proofs) | `bend` + [`nix-effects`](https://github.com/kleisli-io/nix-effects) |
| **Fixpoint** (modules read the merged config) | [`ned`](https://github.com/denful/ned) cycles |

The kernel is ~100 lines. Everything built on top — types, merge strategies, submodules, import trees — uses the same primitives the caller already has.

Zen uses [`nix-effects`](https://github.com/kleisli-io/nix-effects) rotation and scoped handlers to achieve submodules and provide the config fixed-point via Ned streams. This unlocks advanced capabilities that no other Nix module system has: **Actor-like inter-module communication**, **negotiated merge**, **stateful reconciliation**, and **MLTT-verified configs**.


**Performance vs `lib.evalModules`** (10 000 modules, `listOf (submodule {deps = listOf submodule})`):

> [!NOTE]
> Run benchmarks locally using `nix-shell --run 'just bench'`
> Or see [bench workflows](https://github.com/denful/zen/actions/workflows/bench.yml) 


```console
--- Benchmark 1: zen-compat (both load nixpkgs) ---
Benchmark 1: nixpkgs/lib.evalModules
  Time (mean ± σ):     17.282 s ±  2.604 s    [User: 37.514 s, System: 1.791 s]
  Range (min … max):   13.527 s … 20.252 s    20 runs

Benchmark 2: zen/nixmod.evalModules
  Time (mean ± σ):     661.7 ms ± 140.1 ms    [User: 508.7 ms, System: 140.3 ms]
  Range (min … max):   570.4 ms … 1090.1 ms    20 runs

Summary
  zen/nixmod.evalModules ran
   26.12 ± 6.79 times faster than nixpkgs/lib.evalModules
```


```console
--- Benchmark 2: zen-native (no nixpkgs import) vs nixpkgs ---
Benchmark 1: nixpkgs/lib.evalModules
  Time (mean ± σ):     14.020 s ±  0.228 s    [User: 35.402 s, System: 1.479 s]
  Range (min … max):   13.500 s … 14.418 s    20 runs

Benchmark 2: zen-native (no nixpkgs)
  Time (mean ± σ):     201.1 ms ±  10.4 ms    [User: 154.7 ms, System: 39.2 ms]
  Range (min … max):   191.8 ms … 236.0 ms    20 runs

Summary
  zen-native (no nixpkgs) ran
   69.71 ± 3.79 times faster than nixpkgs/lib.evalModules
```

Zen never calls `evalModules` recursively, in nixpkgs this is how a new fixed-point is created for submodules, Zen relies on Ned `scope-d` which uses nix-effect's [`fx.rotate`](https://github.com/kleisli-io/nix-effects/pull/8) to provide scoped handlers with no impact.

---

## Design

### A module system has exactly three jobs

1. Accept contributions from N independent modules.
2. Know what keys are valid and how to merge multiple contributions per key.
3. Let modules read the final merged result while defining it — the fixpoint.

Nixpkgs, adios, and Zen all do these three things. Zen does nothing else.

### Minimalism as constraint

Every feature that could be part of Zen but already exists in `bend`, `ned`, `nix-effects` or `import-tree` is not added. Adding the same feature to Zen would mean maintaining two implementations of the same idea.

The kernel's job is to connect `ned.run` to `bend` lenses. That connection is ~22 lines. Everything built on top of it uses the same primitives the caller already has access to.

## Public surface

```
zen.run  { lens, defs, check?, drivers? }              →  Either errors config
zen.run  [ nixpkgs-style-modules ]                     →  Either errors config
zen.nixmod.evalModules { lib, modules, specialArgs? }  →  { config }
```

All other functionality is `bend.*`, `ned.*` or `fx.*`.


### Schema is a lens, not a declaration

In nixpkgs, an option is a record: `{ type, merge, default, description, ... }`. The system extracts fields and calls them in fixed order, with special handling for each.

In Zen, an option is a single `bend` lens: `[Def] → Either value error`. Merge strategy, type validation (nix-effect's MLTT), and default handling are one composed pipeline — `bend.pipe [ mergeStep typeStep ]`. The kernel calls only `.get`. There is no unpacking, no special cases.

This is intentional. A lens is already the right abstraction: it transforms data or explains why it can't. A wrapper struct around it is indirection without gain.

### Validation is parsing

Zen uses `bend` for all type checking. A type is not a predicate that returns `true`/`false` — it is a lens that returns `right typedValue` or `left error`. Type system are usable from nix-effect's MLTT. This means:

- All errors are collected in one pass, not thrown on first failure.
- Error data is structured — machines can read it, not just humans.
- No `throw`, anywhere in the kernel.

### The fixpoint is explicit

Nixpkgs's `config` reads `config` because `lib.fix` creates a lazy attrset where the fixpoint is implicit — a property of the evaluation engine, not of the module code.

Zen makes it explicit: each `def` is a Cycle function `sources → ST Def`, and `sources.config` is the per-option merged result. `ned.run` wires the cycle. Nix laziness makes it safe. The fixpoint mechanism is inspectable, composable, and auditable without reading the internals of `lib`.

### No imports

Import resolution is not a module system concern. It is a file loading concern.

Nixpkgs modules have an `imports` key that couples file discovery with option evaluation. You cannot evaluate a module set without also discovering which files belong to it. This coupling makes evaluation order hard to reason about and module sets hard to compose as values.

Zen receives a flat list of `defs`. How that list was assembled — from files, from generated code, from a database, from another tool — is not Zen's problem. Use [`import-tree`](https://github.com/vic/import-tree) or plain Nix `import` or anything else.

### Modules communicate via streams, not flags

In nixpkgs, inter-module coordination requires `enable` options: module A checks `config.services.foo.enable`. every module that wants to react to another must know its option path.

Zen modules are isolated. They emit to named sinks and read from named sources. A parent cycle can install a driver that handles "who provides capability X?" without any module knowing any other module's name. This is the same idea as Erlang supervision trees or Akka discovery: actors that communicate through a channel, not by pointing at each other.

This makes modules independently testable and recomposable. It also makes new interaction patterns possible: negotiation ("assign me a free port"), notification ("I am setting this value — does anyone object?"), and stateful reconciliation — all without adding special syntax to the module language.

### Submodules are scope boundaries, not nested evaluations

Nixpkgs creates a new `evalModules` call for each submodule value. At scale — 10 000 modules, each with nested submodule lists — this is O(N × depth) evaluations with full fixpoint setup per call.

In Zen, submodule boundaries are `ned.scope-d` boundaries. Unhandled effects rotate outward to the parent cycle's driver. No recursive kernel invocation. `nix-effects`'s `fx.rotate` has no performance impact and allows well-defined isolation and composition of effectful streams on cycles.

---

## Advanced capabilities

Because modules are streams and the kernel is effect-aware, Zen can implement interaction patterns that are impossible in nixpkgs — without changing the kernel or adding new syntax.

### Actor-like inter-module communication

Modules are isolated. `zen.provide` injects context; `zen.request` consumes it. No module references another by name or option path.

```nix
# Consumer: reads dbUrl from context — zero coupling to provider
connMod = zen.request "conn" ({ dbUrl }: { value = dbUrl; file = "conn.nix"; prio = 100; });

# Provider: wraps consumer with context — consumer doesn't know who provides
connWithCtx = zen.provide { dbUrl = "postgres://localhost/mydb"; } connMod;

zen.run [
  { options.conn = zen.types.str; }
  connWithCtx
]
# → { right = { conn = "postgres://localhost/mydb"; } }
```

Multiple providers can wrap the same consumer. Context is scoped — no global state.

### Negotiated merge

When two modules conflict, Zen uses `fx.effects.conditions` — a Common Lisp-style signal/restart system — to negotiate a resolution. The conflicting merge step produces a `"negotiating"` left value; `zen.run` calls a condition handler that picks a restart. The modules never know about each other or about the resolution policy.

Use `zen.merge.conflict` as the merge strategy for any option that should be negotiable:

```nix
{ options.port = zen.opt zen.merge.conflict zen.lenses.int; }
```

Install a handler in `zen.run { handlers }`:

```nix
zen.run {
  lens = { port = zen.opt zen.merge.conflict zen.lenses.int; };
  defs = [ (zen.defP 50 { port = 8080; }) (zen.defP 100 { port = 9000; }) ];
  handlers = { condition = zen.resolve.useFirst; };  # lowest prio wins
}
# → { right = { port = 8080; } }
```

Built-in resolvers follow the `fx.effects.conditions` handler protocol (`{ param, state } → { resume = { restart, value }; state }`):

```nix
zen.resolve.useFirst  # lowest prio number wins (highest precedence)
zen.resolve.useLast   # highest prio number wins (lowest precedence)
zen.resolve.reject    # returns left { why = "conflict"; defs; }
```

Without a handler, a conflicting `zen.merge.conflict` option is an error. `zen.merge.unique` conflicts are always errors regardless of handlers.

### Stateful reconciliation

`zen.reconcile init step` builds a ned driver that processes a stream of claims with accumulated state — without any module knowing about others.

```nix
# Assign sequential ports to services
portDriver = zen.reconcile 8000
  (port: claim: {
    state  = port + 1;
    result = { service = claim.service; port = port; };
  });

# portDriver :: ST claim → ST { service, port }
# Use directly as a ned driver or wrap in zen.run { drivers = { ports = portDriver; }; }
claims = ned.st.fromList [{ service = "web"; } { service = "db"; }];
(portDriver claims).toList
# → [{ service = "web"; port = 8000; } { service = "db"; port = 8001; }]
```

### Whole-system validation

`zen.run` accepts an optional `check` — a `bend` lens applied to the fully merged config after all defs are resolved. Use `bend.ensure` for cross-field assertions; compose with `bend.pipe` for multiple checks.

```nix
zen.run {
  lens  = { protocol = zen.types.str; port = zen.types.port; };
  defs  = [ (zen.def { protocol = "http"; }) (zen.def { port = 8080; }) ];
  check = bend.ensure (cfg: cfg.port > 1024) "port>1024" bend.identity;
}
```

```nix
# Multiple checks composed
check = bend.pipe [
  (bend.ensure (cfg: cfg.port > 0)    "port>0"  bend.identity)
  (bend.ensure (cfg: cfg.port < 9999) "port<9k" bend.identity)
];
```

### Named channel communication

`zen.run { drivers }` installs custom Ned drivers by name. Modules emit to a named output stream; a driver consumes it. No module references another by name.

```nix
zen.run {
  lens    = { port = zen.types.int; maxConn = zen.types.int; };
  defs    = [
    (_: { port = 8080; portOut = ned.st 8080; })
    (sources: { maxConn = sources.portOut.map (p: { value = p * 10; file = "t"; prio = 100; }); })
  ];
  drivers = { portOut = x: x; };
}
# → { right = { port = 8080; maxConn = 80800; } }
```

Use `zen.reconcile` as a driver to process a named stream with accumulated state (see Stateful reconciliation above).

### MLTT type verification

`zen.satisfy` wraps any predicate or type with a `.check` method as a bend lens. Use anywhere `zen.lenses.*` can be used — submod schemas, `zen.types.listOf`, or directly in `zen.opt`.

```nix
# MLTT-verified option
{ options.port = zen.opt zen.merge.unique (zen.satisfy fx.types.Int); }

# In submod schema — MLTT-verified fields
{ options.db = zen.types.submod { host = zen.satisfy fx.types.String; port = zen.satisfy fx.types.Int; }; }

# MLTT list: every element verified
{ options.tags = zen.types.listOf (zen.satisfy (fx.types.ListOf fx.types.String)); }

# zen.satisfy T  works with any type having .check, or a plain boolean predicate
(zen.satisfy fx.types.Int).get 42       # → { right = 42; }
(zen.satisfy fx.types.Int).get "oops"   # → { left = "oops"; }
(zen.satisfy builtins.isInt).get 42     # → { right = 42; }
```

The proof is a bend lens in the pipeline. `bend.pipe` carries it. The kernel never sees it — it just calls `.get`.

---

--

## [zer0ver](https://0ver.org)

Zen uses 0-based versioning. `v0.x`

--

## Install

Zen depends on [Bend](https://github.com/denful/bend) (for Structured Lens / Validation / Merging), [Ned](https://github.com/denful/ned) (for cycle-based fixed-point) and [nix-effects](https://github.com/kleisli-io/nix-effects) (streams, effect rotation and scoped handlers for submoules)

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

The simplest form is a flat list of nixpkgs-style modules. Each module declares its options and config in the same attrset:

```nix
zen.run [
  { options.port = zen.withDefault 8080 zen.types.int; }
  { options.host = zen.withDefault "localhost" zen.types.str; }
  { config.port = 9000; }
]
# → { right = { port = 9000; host = "localhost"; } }
```

Modules can read the final merged config — this is the fixpoint. In the flat list form, a function module receives plain config values:

```nix
zen.run [
  { options.port = zen.withDefault 8080 zen.types.int; }
  { options.host = zen.types.str; }
  { config.port = 9000; }
  # fixpoint: reads merged port to derive host
  (cfg: { config.host = "localhost:${toString cfg.port}"; })
]
# → { right = { port = 9000; host = "localhost:9000"; } }
```

Or pass `{ lens, defs }` explicitly for lower-level control:

```nix
zen.run {
  lens = {
    port = zen.withDefault 8080 zen.types.int;
    host = zen.withDefault "localhost" zen.types.str;
  };
  defs = [
    (zen.def { port = 9000; })         # simple one-liner, priority 100
    (zen.defP 50 { port = 8080; })     # explicit priority
  ];
}
```

## DX Layer

Zen ships `zen.types`, `zen.lenses`, `zen.merge`, `zen.opt`, and `zen.withDefault` so you never write merge boilerplate.

### Types

| Lens | Merge | Nix value |
|------|-------|-----------|
| `zen.types.int` | unique | integer |
| `zen.types.str` | unique | string |
| `zen.types.bool` | unique | boolean |
| `zen.types.float` | unique | float |
| `zen.types.any` | unique | anything |
| `zen.types.nonEmptyStr` | unique | non-empty string |
| `zen.types.singleLineStr` | unique | no-newline string |
| `zen.types.strMatching pat` | unique | regex-matched string |
| `zen.types.port` | unique | 0–65535 |
| `zen.types.positiveInt` | unique | > 0 |
| `zen.types.unsignedInt` | unique | >= 0 |
| `zen.types.intBetween lo hi` | unique | lo..hi |
| `zen.types.listOf t` | concat | list of `t` |
| `zen.types.attrsOf t` | attrs | attrset of `t` |
| `zen.types.nullOr t` | unique | null or `t` |
| `zen.types.submod schema` | unique | nested module (one def) |
| `zen.types.attrsSubmod schema` | attrs | nested module (multi-def) |
| `zen.types.sub` | unique | nested cycle with own fixpoint (`zen.sub`) |

`zen.withDefault value lens` — return `value` when no defs provided.

`zen.opt m t` — explicit fuse: pick your merge strategy from `zen.merge.*` (unique, first, last, concat, attrs, conflict).

`zen.merge.conflict` — like `unique` but conflict is negotiable: provide a handler via `zen.run { handlers = { condition = zen.resolve.useFirst; }; }` to resolve at the call site.

`zen.def attrs` — one-line def (prio 100). `zen.defP prio attrs` — def with explicit priority.

> **Note:** `zen.types.listOf`, `zen.types.attrsOf`, `zen.types.submod`, and `zen.types.attrsSubmod` take value-level lenses as element/field types — use `zen.lenses.*` (mirrors `zen.types.*` but without merge) or raw `bend.*`.

### Submodules

`zen.types.submod schema` validates an attrset value against a schema using `bend.recordAll` — pure bend, zero ned overhead. Schema takes value-level lenses (`zen.lenses.*` or `bend.*`).

`zen.types.attrsSubmod schema` — same but with attrs merge: multiple defs can each contribute a partial attrset to the same submodule field.

```nix
# Unique submod: one def owns the entire attrset
{ db = zen.types.submod { host = zen.lenses.str; port = zen.lenses.int; }; }

# Attrs submod: multiple defs contribute partial attrsets
{ db = zen.types.attrsSubmod { host = zen.lenses.str; port = zen.lenses.int; }; }
# Module A: zen.def { db = { host = "localhost"; }; }
# Module B: zen.def { db = { port = 5432; }; }
# Result:   { db = { host = "localhost"; port = 5432; } }
```

### zen.sub — nested cycles with own fixpoint

`zen.sub name mods` creates a nested cycle inside a `zen.types.sub` field. Unlike `zen.types.submod`, it runs a full Ned cycle — inner modules get their own merged config and can contribute to `zen.types.sub` fields independently.

```nix
zen.run [
  { options.db = zen.types.sub; }
  (zen.sub "db" [
    { options.host = zen.withDefault "localhost" zen.types.str; config.host = "db.internal"; }
    { options.port = zen.withDefault 5432 zen.types.port; }
  ])
]
# → { right = { db = { host = "db.internal"; port = 5432; } } }
```

`zen.sub` accepts either a flat list of modules or an attrset `{ lens, defs, check?, context? }`.

**`check`** — a `bend` lens applied to the inner merged config. Validated after the inner cycle resolves:

```nix
(zen.sub "db" {
  lens  = { port = zen.withDefault 5432 zen.types.port; };
  defs  = [ (zen.def { port = 80; }) ];
  check = bend.ensure (cfg: cfg.port > 1024) "port>1024" bend.identity;
})
# → left (port 80 fails > 1024)
```

**`context`** — a function `outerCfg → attrset` that injects outer values into the inner cycle as request context. Inner defs can then read those values via `zen.request`:

```nix
# outer env=dev causes inner port to use 5433 instead of 5432
(zen.sub "db" {
  lens    = { port = zen.withDefault 5432 zen.types.port; };
  context = outerCfg: { appEnv = outerCfg.env or "prod"; };
  defs    = [ (zen.request "port" ({ appEnv }: { value = if appEnv == "dev" then 5433 else 5432; file = "t"; prio = 100; })) ];
})
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
```
