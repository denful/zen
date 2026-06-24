help:
  just -l

docs:
  cd docs && pnpm run dev

zerover:
  echo "obase=2; $(date +%s)" | bc

fmt *args:
  treefmt {{args}}

ci:
  just fmt --ci --no-cache
  just test

test suite="all" *args:
  nix-unit --expr 'let x = import ./tests.nix; in if "{{suite}}" == "all" then x else x.{{suite}}' {{args}}

bench runs="10" warmup="3":
  cd benchmarks && RUNS={{runs}} WARMUP={{warmup}} ./bench.sh

# narrated investor showcase — all acts (`just demo`) or one (`just demo actor`)
demo act="all":
  ./demos/showcase.sh {{act}}

# terse side-by-side demos, nixpkgs vs dzm, no narration (`just demos`)
demos:
  ./demos/run.sh

