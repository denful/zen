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

Zen is a thin kernel built to provide only essential features a module system *must* have:

| What | How |
|------|-----|
| **N → 1** (how to merge module contribs) | [`bend`](https://github.com/denful/bend) lenses |
| **Types** (what is valid) | `bend` + [`nix-effects`](https://github.com/kleisli-io/nix-effects) MLTT types and proofs |
| **Fixpoint** (modules read the merged config) | [`ned`](https://github.com/denful/ned) cycles |

Everything else — types, merge strategies, submodules, import-trees — lives outside the kernel, in `bend`, `ned`, `nix-effects`, or caller code.


**Performance vs `lib.evalModules`** (10 000 modules, `listOf (submodule {deps = listOf submodule})`):

> [!NOTE]
> Run benchmarks locally using `nix-shell --run 'just bench'`
> Or see [bench workflows](https://github.com/denful/zen/actions/workflows/bench.yml) 

| | Wall clock | vs nixpkgs |
|--|--|--|
| `lib.evalModules` | 12.3 s | baseline |
| `zen.nixmod.evalModules` | 610 ms | **20×** |
| zen without nixpkgs import | 293 ms | **42×** |
| eval-only (estimated) | ~110 ms | **~100×** |

Zen never calls `evalModules` recursively, in nixpkgs this is how a new fixed-point is created for submodules, Zen relies on Ned `scope-d` which uses nix-effect's [`fx.rotate`](https://github.com/kleisli-io/nix-effects/pull/8) to provide scoped handlers with no impact.

---

## Design

### A module system has exactly three jobs

1. Accept contributions from N independent modules.
2. Know what keys are valid and how to merge multiple contributions per key.
3. Let modules read the final merged result while defining it — the fixpoint.

Nixpkgs, adios, and Zen all do these three things. Zen does nothing else.

### Minimalism as constraint

Every feature that could be added to Zen already exists in `bend` or `ned`. Adding the same feature to Zen would mean maintaining two implementations of the same idea.

The kernel's job is to connect `ned.run` to `bend` lenses. That connection is ~22 lines. Everything built on top of it uses the same primitives the caller already has access to.

## Public surface

```
zen.run    { lens, defs }                              →  Either errors config
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

In Zen, submodule boundaries are `ned.scope-d` boundaries. Unhandled effects rotate outward to the parent cycle's driver. No recursive kernel invocation. nix-effect's fx.rotate has no performance impact and allows well defined isolation / composition of effectful streams on cycles.

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

```nix
let
  inherit (zen) bend ned;
  inherit (builtins) length head;

  # Schema: one bend lens per option.
  # lens.get :: [Def] → Either value error
  # You compose merge + type yourself — no hidden magic.
  uniqueInt = bend.pipe [
    (bend.parse (defs:
      if defs == []            then bend.left  { why = "required"; }
      else if length defs == 1 then bend.right (head defs).value
      else                          bend.left  { why = "conflict"; inherit defs; }
    ) bend.identity)
    bend.int
  ];

  # Def: a function srcs → ST Def (stream of contributions)
  portMod = _srcs: ned.st.fromList [
    { name = "port"; value = 8080; file = ./port.nix; prio = 100; }
  ];

  hostMod = srcs:
    # Defs can read the final merged config — this is the fixpoint.
    let port = if srcs.config.port ? right then srcs.config.port.right else 80;
    in ned.st.fromList [
      { name = "host"; value = "localhost:${toString port}"; file = ./host.nix; prio = 100; }
    ];

in
zen.run {
  lens = { port = uniqueInt; host = uniqueInt; };
  defs = [ portMod hostMod ];
}
# → { right = { port = 8080; host = "localhost:8080"; }; }
```

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
