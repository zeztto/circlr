#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
circlr_module_cache="${CIRCLR_MODULE_CACHE_PATH:-$PWD/.build/module-cache}"
export CLANG_MODULE_CACHE_PATH="$circlr_module_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$circlr_module_cache"
exec swift "$@" --disable-sandbox --cache-path .build/cache -Xswiftc -module-cache-path -Xswiftc "$circlr_module_cache"
