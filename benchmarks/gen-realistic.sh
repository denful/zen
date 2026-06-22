#!/usr/bin/env bash
# Generator for REALISTIC NixOS-config-shaped workload, byte-faithful across
# zen and nixpkgs lib.evalModules.
#
# Shape (per "service module" i, M of them):
#   - scalar opts: enable(bool), port(int), user(str), logLevel(str w/ mkDefault)
#   - attrsOf submodule collection `instances` with K entries; each entry a
#     submodule { command(str); restart(str); priority(int); }  (systemd.services-style)
#   - list opt `paths` (listOf str) contributed by 2 defs via mkMerge (concat merge)
#   - SPARSE cross-ref: every 4th module's `port` reads previous module's `port`+1
#     zen: literal `{ port_k }: port_k + 1` pattern (edge-local dep via functionArgs)
#     nixpkgs: `config.port_k + 1` (module-arg config record)
#   - mkDefault on logLevel (overridden by a bare def in a separate module)
#   - mkForce on user_0 (force beats bare)
#
# Args: $1=ENGINE (zen|nixpkgs)  $2=M (num service modules)  $3=K (entries per collection)
#
# The zen import path is resolved relative to THIS script's directory (../.)
# so the fixture works from any clone location, not just /home/vic/hk/zen.
set -euo pipefail
ENGINE="$1"; M="$2"; K="$3"
DIR="$(cd "$(dirname "$0")" && pwd)"
DZM_PATH="${DZM_PATH:-${DIR}/..}"

gen_zen() {
  cat <<HEADER
let
  zen = import ${DZM_PATH} { };
  t = zen.t;
  m = zen.m;
HEADER
  cat <<'SCHEMA'
  instType = t.attrsOf (t.submod {
    command = t.str;
    restart = t.str;
    priority = t.int;
  });
SCHEMA
  echo "  modules = ["
  for ((i=0; i<M; i++)); do
    echo "    {"
    echo "      options.enable_${i} = zen.opt m.unique t.bool;"
    echo "      options.port_${i} = zen.opt m.unique t.int;"
    echo "      options.user_${i} = zen.opt m.unique t.str;"
    echo "      options.logLevel_${i} = zen.opt m.unique t.str;"
    echo "      options.paths_${i} = t.listOf t.str;"
    echo "      options.instances_${i} = instType;"
    echo "      config.enable_${i} = true;"
    # SPARSE cross-ref: every 4th module resets to base port; others read prev+1
    # zen MUST use literal destructuring pattern for edge-local dep detection
    if (( i % 4 == 0 || i == 0 )); then
      echo "      config.port_${i} = $((8000 + i));"
    else
      echo "      config.port_${i} = { port_$((i-1)) }: port_$((i-1)) + 1;"
    fi
    echo "      config.user_${i} = \"svc${i}\";"
    # logLevel: mkDefault overridden by a bare def in the override module below
    echo "      config.logLevel_${i} = zen.mkDefault \"info\";"
    # paths: two contributions merged (concat merge)
    echo "      config.paths_${i} = zen.mkMerge ["
    echo "        [ \"/var/lib/svc${i}\" ]"
    echo "        [ \"/etc/svc${i}\" ]"
    echo "      ];"
    # attrsSubmod collection: K entries (systemd.services-style)
    echo "      config.instances_${i} = {"
    for ((j=0; j<K; j++)); do
      echo "        inst${j} = { command = \"/bin/run${j}\"; restart = \"on-failure\"; priority = ${j}; };"
    done
    echo "      };"
    echo "    }"
  done
  # override module: bare defs beat mkDefault on logLevel; mkForce beats bare on user_0
  echo "    {"
  for ((i=0; i<M; i++)); do
    echo "      config.logLevel_${i} = \"warn\";"
  done
  echo "      config.user_0 = zen.mkForce \"root\";"
  echo "    }"
  echo "  ];"
  echo "in"
  echo "(zen.run { inherit modules; }).right"
}

gen_nixpkgs() {
  cat <<'HEADER'
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
HEADER
  cat <<'SCHEMA'
  instType = lib.types.attrsOf (lib.types.submodule {
    options.command = lib.mkOption { type = lib.types.str; };
    options.restart = lib.mkOption { type = lib.types.str; };
    options.priority = lib.mkOption { type = lib.types.int; };
  });
SCHEMA
  echo "  modules = ["
  for ((i=0; i<M; i++)); do
    echo "    ({ config, ... }: {"
    echo "      options.enable_${i} = lib.mkOption { type = lib.types.bool; };"
    echo "      options.port_${i} = lib.mkOption { type = lib.types.int; };"
    echo "      options.user_${i} = lib.mkOption { type = lib.types.str; };"
    echo "      options.logLevel_${i} = lib.mkOption { type = lib.types.str; };"
    echo "      options.paths_${i} = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };"
    echo "      options.instances_${i} = lib.mkOption { type = instType; default = {}; };"
    echo "      config.enable_${i} = true;"
    if (( i % 4 == 0 || i == 0 )); then
      echo "      config.port_${i} = $((8000 + i));"
    else
      echo "      config.port_${i} = config.port_$((i-1)) + 1;"
    fi
    echo "      config.user_${i} = \"svc${i}\";"
    echo "      config.logLevel_${i} = lib.mkDefault \"info\";"
    echo "      config.paths_${i} = lib.mkMerge ["
    echo "        [ \"/var/lib/svc${i}\" ]"
    echo "        [ \"/etc/svc${i}\" ]"
    echo "      ];"
    echo "      config.instances_${i} = {"
    for ((j=0; j<K; j++)); do
      echo "        inst${j} = { command = \"/bin/run${j}\"; restart = \"on-failure\"; priority = ${j}; };"
    done
    echo "      };"
    echo "    })"
  done
  echo "    {"
  for ((i=0; i<M; i++)); do
    echo "      config.logLevel_${i} = \"warn\";"
  done
  echo "      config.user_0 = lib.mkForce \"root\";"
  echo "    }"
  echo "  ];"
  echo "in"
  echo "(lib.evalModules { inherit modules; }).config"
}

if [[ "$ENGINE" == "zen" ]]; then gen_zen; else gen_nixpkgs; fi
