#!/bin/bash
# ==============================================================================
# Deployment Validation Script
# ==============================================================================
# Orchestrates Salesforce deployment validation with intelligent test selection
# and fallback strategies to ensure deployment quality.
#
# Test Execution Strategy:
#   1. Attempt RunSpecifiedTests with mapped test classes
#   2. Fallback to RunLocalTests if coverage insufficient
#   3. Skip tests for metadata-only deployments (NoTestRun)
#
# Outputs:
#   - reports/deploy-report.json: Deployment validation results
#   - reports/validation-summary.txt: Human-readable summary
# ==============================================================================

set -euo pipefail

echo ""
echo "🚀 STAGE 5B: DEPLOYMENT VALIDATION"
echo "================================"

# Create reports directory
mkdir -p reports

# Initialize default report
echo '{"result":{"status":"Failed","message":"No deploy run performed"}}' > reports/deploy-report.json
echo "" > reports/validation-summary.txt

# Logging function
summary() {
  echo "$1" | tee -a reports/validation-summary.txt
}

summary "🚀 Starting deployment validation process..."

# Check if there's deployable metadata
if [ -d "delta/force-app" ] && [ "$(find delta/force-app -type f 2>/dev/null | wc -l)" -gt 0 ]; then
  summary "📦 Deployable metadata detected in delta package"

  # Check if Apex components exist (requiring test execution)
  if find delta/force-app -name "*.cls" -o -name "*.trigger" 2>/dev/null | grep -q .; then
    summary "🔧 Apex components detected - test execution required"

    echo ""
    echo "⚙️  EXECUTING DEPLOYMENT VALIDATION WITH TESTS"
    echo "=============================================="

    # Try intelligent test selection first
    if [ -n "${RELATED_TESTS:-}" ]; then
      RELATED_TESTS_CSV=$(echo "$RELATED_TESTS" | xargs -n1 | paste -sd, - || echo "")
      summary "🎯 Using intelligent test selection: ${RELATED_TESTS_CSV}"

      echo ""
      echo "📋 Test Strategy: RunSpecifiedTests"
      echo "  • Tests: $RELATED_TESTS_CSV"
      echo "  • Validation Mode: Dry-run (check-only)"
      echo ""

      summary "🔄 Running deployment validation with mapped tests..."
      
      if sf project deploy start \
        --source-dir delta/force-app \
        --target-org sandbox \
        --dry-run \
        --test-level RunSpecifiedTests \
        --tests "$RELATED_TESTS_CSV" \
        --json > reports/deploy-report.json 2>&1; then
        summary "✅ Mapped-tests deploy validation: Succeeded"
      else
        summary "⚠️  Mapped-tests deploy validation: Failed (see reports/deploy-report.json). Will retry with RunLocalTests."
      fi

      # Calculate coverage
      COVERAGE=0
      if jq -e '.result.details.runTestResult.codeCoverage' reports/deploy-report.json >/dev/null 2>&1; then
        COVERAGE=$(jq -r '[.result.details.runTestResult.codeCoverage[]? | (.coveredPercent // 0)] | (if length>0 then (add/length) else 0 end)' reports/deploy-report.json 2>/dev/null || echo "0")
        COVERAGE=${COVERAGE%.*}
      fi
      summary "📊 Coverage from mapped-tests run: ${COVERAGE}%"

      # Check if fallback needed
      if [ "$COVERAGE" -lt "${COVERAGE_THRESHOLD}" ] || jq -e '.result.status != "Succeeded"' reports/deploy-report.json >/dev/null 2>&1; then
        summary "⚠️  Triggering fallback: RunLocalTests (either mapped run failed or coverage < ${COVERAGE_THRESHOLD}%)."
        
        echo ""
        echo "📋 Fallback Test Strategy: RunLocalTests"
        echo "  • Tests: All local tests in org"
        echo "  • Validation Mode: Dry-run (check-only)"
        echo ""
        
        if sf project deploy start \
          --source-dir delta/force-app \
          --target-org sandbox \
          --dry-run \
          --test-level RunLocalTests \
          --json > reports/deploy-report-coverage.json 2>&1; then
          summary "✅ Fallback RunLocalTests: Succeeded"
          mv reports/deploy-report-coverage.json reports/deploy-report.json
        else
          summary "❌ Fallback RunLocalTests: Failed (see reports/deploy-report-coverage.json)"
          mv reports/deploy-report-coverage.json reports/deploy-report.json || true
        fi
      else
        summary "✅ Mapped-tests coverage meets threshold; no fallback required."
      fi

    else
      summary "ℹ️  No mapped tests found; running RunLocalTests."
      
      echo ""
      echo "📋 Test Strategy: RunLocalTests"
      echo "  • Tests: All local tests in org"
      echo "  • Validation Mode: Dry-run (check-only)"
      echo ""
      
      if sf project deploy start \
        --source-dir delta/force-app \
        --target-org sandbox \
        --dry-run \
        --test-level RunLocalTests \
        --json > reports/deploy-report.json 2>&1; then
        summary "✅ RunLocalTests deploy validation: Succeeded"
      else
        summary "❌ RunLocalTests deploy validation: Failed (see reports/deploy-report.json)"
      fi
    fi

  else
    summary "📄 Metadata-only deployment (LWC/CustomObject/Flow) - no test execution required"
    
    echo ""
    echo "⚙️  EXECUTING METADATA-ONLY DEPLOYMENT VALIDATION"
    echo "==============================================="
    echo ""
    echo "📋 Test Strategy: NoTestRun"
    echo "  • Validation Mode: Dry-run (check-only)"
    echo "  • Components: Metadata only (no Apex code)"
    echo ""
    
    sf project deploy start \
      --source-dir delta/force-app \
      --target-org sandbox \
      --dry-run \
      --test-level NoTestRun \
      --json > reports/deploy-report.json 2>&1 || true
    
    summary "✅ Metadata-only validation completed"
  fi

else
  summary "📋 No deployable metadata found in delta. Skipping validation."
  echo '{"result":{"status":"Skipped","message":"No changes to deploy"}}' > reports/deploy-report.json
fi

summary "🏁 Deployment validation process completed"

echo ""
echo "✅ STAGE 5B COMPLETED: Deployment validation finished"
echo "================================================"
