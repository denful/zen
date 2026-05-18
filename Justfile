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

bench-export file="benchmarks/results.md" runs="20" warmup="5":
  cd benchmarks && RUNS={{runs}} WARMUP={{warmup}} EXPORT={{file}} ./bench.sh
