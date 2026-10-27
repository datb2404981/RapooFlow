#!/bin/zsh
set -euo pipefail

tests_dir="${0:A:h}"
project_dir="${tests_dir:h}"
bin_path="/tmp/rapooflow-tests"

echo "Building RapooFlow Multi-Tier Test Suite..."
swiftc -O \
  "$project_dir/Sources/Preferences.swift" \
  "$project_dir/Sources/ScrollMotion.swift" \
  "$tests_dir/TestHarness.swift" \
  "$tests_dir/Tier1_UnitMathTests.swift" \
  "$tests_dir/Tier2_EventPipelineTests.swift" \
  "$tests_dir/Tier3_SteppedClockTests.swift" \
  "$tests_dir/Tier4_IntegrationTests.swift" \
  "$tests_dir/TestRunner.swift" \
  "$tests_dir/main.swift" \
  -framework AppKit -framework ApplicationServices -framework IOKit -framework CoreVideo \
  -o "$bin_path"

echo "Executing Test Runner..."
"$bin_path" "$@"
