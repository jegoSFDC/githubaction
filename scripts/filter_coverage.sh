#!/bin/bash
# ==============================================================================
# Coverage Data Filtering Script
# ==============================================================================
# Filters deployment validation coverage data to include only Apex classes
# that are part of the current delta package, providing focused coverage metrics.
#
# Purpose:
#   - Reduce noise from unrelated classes in coverage reports
#   - Focus on coverage metrics for classes being deployed
#   - Enable accurate coverage threshold validation for changed components
#
# Algorithm:
#   1. Validate deploy report contains coverage data
#   2. Extract delta class names for filtering
#   3. Filter coverage data to delta classes only
#   4. Update deploy report with filtered results
#
# Input:
#   - reports/deploy-report.json: Raw deployment report with full coverage
#   - DELTA_APEX_CLASSES: Space-separated list of delta class names
#
# Output:
#   - reports/deploy-report.json: Updated with filtered coverage data
# ==============================================================================

set -euo pipefail

echo ""
echo "🚀 STAGE 5C: COVERAGE DATA FILTERING"
echo "=================================="
echo "🔍 Filtering coverage data for delta classes only..."

# Validate prerequisites
echo "🔍 Validating prerequisites..."
if [ ! -f reports/deploy-report.json ]; then
  echo "ℹ️  No deploy report found - this is expected for metadata-only deployments"
  echo "📄 Creating placeholder coverage report for metadata-only deployment..."
  echo '{"result":{"status":"Skipped","message":"No Apex deployment - coverage filtering not applicable"}}' > reports/deploy-report.json
  exit 0
fi

if [ -z "${DELTA_APEX_CLASSES:-}" ]; then
  echo "ℹ️  No delta classes specified - skipping coverage filtering"
  exit 0
fi

echo "📋 Delta classes for coverage filtering: $DELTA_APEX_CLASSES"

# Create filtered coverage report using jq
echo "⚙️  Processing coverage data with jq filtering..."
if jq --arg delta_classes "$DELTA_APEX_CLASSES" '
  if .result.details.runTestResult.codeCoverage then
    .result.details.runTestResult.codeCoverage = [
      .result.details.runTestResult.codeCoverage[]? |
      select(.name as $name | ($delta_classes | split(" ") | index($name)))
    ]
  else
    .
  end
' reports/deploy-report.json > reports/deploy-report-filtered.json 2>/dev/null; then

  # Replace original report with filtered version
  echo "📄 Replacing original report with filtered version..."
  mv reports/deploy-report-filtered.json reports/deploy-report.json
  echo "✅ Coverage data successfully filtered for delta classes"

else
  echo "⚠️  Coverage filtering failed - retaining original report"
  exit 1
fi

echo "📊 Filtered coverage report contains:"
echo "  • $(jq '.result.details.runTestResult.codeCoverage | length' reports/deploy-report.json 2>/dev/null || echo '0') classes"
echo "  • Coverage limited to delta package scope"

echo ""
echo "✅ STAGE 5C COMPLETED: Coverage filtering finished"
echo "============================================="
