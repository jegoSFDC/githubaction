#!/bin/bash
# ==============================================================================
# Deployment Dry-Run Validation
# ==============================================================================
# Executes a dry-run (check-only) deployment validation to Salesforce sandbox.
# Tests the deployment without actually deploying to ensure quality.
#
# Validation Strategy:
#   1. Try RunSpecifiedTests with mapped test classes
#   2. Fallback to RunLocalTests if needed
#   3. Skip tests for metadata-only deployments (NoTestRun)
#
# Output:
#   - Deployment validation results
#   - Test execution summary
#   - Code coverage metrics
#   - Quality gate validation
# ==============================================================================

set -euo pipefail

echo ""
echo "🚀 STAGE 6: DRY-RUN VALIDATION & QUALITY GATES SUMMARY"
echo "======================================================"
echo "🔍 Validating deployment with check-only mode (no actual deployment)..."

# Create reports directory
mkdir -p reports

# Initialize default report
echo '{"result":{"status":"Failed","message":"No deploy run performed"}}' > reports/deploy-report.json
echo "" > reports/validation-summary.txt

# Logging function
summary() {
  echo "$1" | tee -a reports/validation-summary.txt
}

# Check if there's deployable metadata
if [ -d "delta/force-app" ] && [ "$(find delta/force-app -type f 2>/dev/null | wc -l)" -gt 0 ]; then
  summary "📦 Deployable metadata detected"

  # Check if Apex components exist (requiring test execution)
  if find delta/force-app -name "*.cls" -o -name "*.trigger" 2>/dev/null | grep -q .; then
    summary "🧪 Apex components detected - running tests"

    echo ""
    echo "⚙️  EXECUTING DRY-RUN VALIDATION WITH TESTS"
    echo "==========================================="

    # Try intelligent test selection first
    if [ -n "${RELATED_TESTS:-}" ]; then
      RELATED_TESTS_CSV=$(echo "$RELATED_TESTS" | xargs -n1 | paste -sd, - || echo "")
      summary "🎯 Test Strategy: RunSpecifiedTests"
      summary "   Tests: ${RELATED_TESTS_CSV}"

      echo ""
      echo "📋 Validation Details:"
      echo "  • Mode: Dry-run (check-only - no actual deployment)"
      echo "  • Tests: $RELATED_TESTS_CSV"
      echo "  • Environment: Sandbox"
      echo ""

      summary "🔄 Running validation..."
      
      if sf project deploy start \
        --source-dir delta/force-app \
        --target-org sandbox \
        --dry-run \
        --test-level RunSpecifiedTests \
        --tests "$RELATED_TESTS_CSV" \
        --json > reports/deploy-report.json 2>&1; then
        summary "✅ Validation passed with mapped tests"
      else
        summary "⚠️  Validation failed with mapped tests - trying fallback"
      fi

      # Calculate coverage
      COVERAGE=0
      if jq -e '.result.details.runTestResult.codeCoverage' reports/deploy-report.json >/dev/null 2>&1; then
        COVERAGE=$(jq -r '[.result.details.runTestResult.codeCoverage[]? | (.coveredPercent // 0)] | (if length>0 then (add/length) else 0 end)' reports/deploy-report.json 2>/dev/null || echo "0")
        COVERAGE=${COVERAGE%.*}
      fi
      summary "📊 Coverage: ${COVERAGE}%"

      # Check if fallback needed
      if [ "$COVERAGE" -lt "${COVERAGE_THRESHOLD}" ] || jq -e '.result.status != "Succeeded"' reports/deploy-report.json >/dev/null 2>&1; then
        summary "⚠️  Fallback required (coverage < ${COVERAGE_THRESHOLD}% or validation failed)"
        summary "🔄 Test Strategy: RunLocalTests (all org tests)"
        
        echo ""
        echo "📋 Fallback Validation:"
        echo "  • Mode: Dry-run (check-only)"
        echo "  • Tests: All local tests in org"
        echo ""
        
        if sf project deploy start \
          --source-dir delta/force-app \
          --target-org sandbox \
          --dry-run \
          --test-level RunLocalTests \
          --json > reports/deploy-report-coverage.json 2>&1; then
          summary "✅ Fallback validation passed"
          mv reports/deploy-report-coverage.json reports/deploy-report.json
        else
          summary "❌ Fallback validation failed"
          mv reports/deploy-report-coverage.json reports/deploy-report.json || true
        fi
      fi

    else
      summary "🔄 Test Strategy: RunLocalTests (no mapped tests)"
      
      echo ""
      echo "📋 Validation Details:"
      echo "  • Mode: Dry-run (check-only - no actual deployment)"
      echo "  • Tests: All local tests in org"
      echo "  • Environment: Sandbox"
      echo ""
      
      if sf project deploy start \
        --source-dir delta/force-app \
        --target-org sandbox \
        --dry-run \
        --test-level RunLocalTests \
        --json > reports/deploy-report.json 2>&1; then
        summary "✅ Validation passed"
      else
        summary "❌ Validation failed"
      fi
    fi

  else
    summary "📄 Metadata-only deployment (LWC/Config) - no tests required"
    
    echo ""
    echo "⚙️  EXECUTING METADATA-ONLY VALIDATION"
    echo "====================================="
    echo ""
    echo "📋 Validation Details:"
    echo "  • Mode: Dry-run (check-only - no actual deployment)"
    echo "  • Type: Metadata-only (no Apex code)"
    echo "  • Environment: Sandbox"
    echo ""
    
    sf project deploy start \
      --source-dir delta/force-app \
      --target-org sandbox \
      --dry-run \
      --test-level NoTestRun \
      --json > reports/deploy-report.json 2>&1 || true
    
    summary "✅ Metadata validation completed"
  fi

else
  summary "ℹ️  No deployable metadata - skipping validation"
  echo '{"result":{"status":"Skipped","message":"No changes to deploy"}}' > reports/deploy-report.json
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 DRY-RUN VALIDATION & QUALITY GATES SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract Code Analyzer results
APEX_VIOLATIONS=0
LWC_VIOLATIONS=0

if [ -f reports/apex.json ]; then
  APEX_VIOLATIONS=$(jq '.violations | length' reports/apex.json 2>/dev/null || echo "0")
fi

if [ -f reports/lwc.json ]; then
  LWC_VIOLATIONS=$(jq '.violations | length' reports/lwc.json 2>/dev/null || echo "0")
fi

TOTAL_VIOLATIONS=$((APEX_VIOLATIONS + LWC_VIOLATIONS))

# Extract deployment validation metrics
STATUS="Failed"
COMPONENT_FAIL_COUNT=0
TEST_FAIL_COUNT=0
COVERAGE=0

if [ -f reports/deploy-report.json ]; then
  STATUS=$(jq -r '.result.status // "Failed"' reports/deploy-report.json 2>/dev/null || echo "Failed")
  
  if jq -e '.result.details.componentFailures' reports/deploy-report.json >/dev/null 2>&1; then
    COMPONENT_FAIL_COUNT=$(jq '.result.details.componentFailures | length' reports/deploy-report.json 2>/dev/null || echo "0")
  fi
  
  if jq -e '.result.details.runTestResult.failures' reports/deploy-report.json >/dev/null 2>&1; then
    TEST_FAIL_COUNT=$(jq '.result.details.runTestResult.failures | length' reports/deploy-report.json 2>/dev/null || echo "0")
  fi
  
  if jq -e '.result.details.runTestResult.codeCoverage' reports/deploy-report.json >/dev/null 2>&1; then
    COVERAGE=$(jq -r '[.result.details.runTestResult.codeCoverage[]? | (.coveredPercent // 0)] | (if length>0 then (add/length) else 0 end)' reports/deploy-report.json 2>/dev/null || echo "0")
    COVERAGE=${COVERAGE%.*}
  fi
fi

echo ""
echo "🔍 Code Quality Analysis:"
echo "  • Total Code Violations: $TOTAL_VIOLATIONS (Apex: $APEX_VIOLATIONS, LWC: $LWC_VIOLATIONS)"
echo ""
echo "🧪 Deployment Validation:"
echo "  • Validation Status: ${STATUS}"
echo "  • Component Failures: ${COMPONENT_FAIL_COUNT}"
echo "  • Test Failures: ${TEST_FAIL_COUNT}"
echo "  • Code Coverage: ${COVERAGE}% (threshold: ${COVERAGE_THRESHOLD}%)"
echo ""

# Display detailed failure information if needed
if [ "${COMPONENT_FAIL_COUNT}" -gt 0 ] || [ "${TEST_FAIL_COUNT}" -gt 0 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⚠️  ISSUES DETECTED"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Display test failures
  if [ "${TEST_FAIL_COUNT}" -gt 0 ]; then
    echo ""
    echo "🧪 Test Failures:"
    jq -r '.result.details.runTestResult.failures[]? |
      "  ❌ \(.name).\(.methodName // "unknown")\n     \(.message // "" )" ' reports/deploy-report.json 2>/dev/null \
      | sed -e "s/<br>/\\n/g" -e "s/<[^>]*>//g" \
      | head -20 || true
  fi

  # Display component failures
  if [ "${COMPONENT_FAIL_COUNT}" -gt 0 ]; then
    echo ""
    echo "🔧 Component Failures:"
    jq -r '.result.details.componentFailures[]? | "  ❌ " + (.fileName // .name) + ": " + (.problem // "Unknown")' reports/deploy-report.json 2>/dev/null | head -10 || true
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 QUALITY GATE VALIDATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Validate quality gates
if [ "$STATUS" = "Succeeded" ]; then
  echo "✅ Validation: PASSED"
  echo "✅ All quality gates met"
  echo ""
  echo "🎉 DEPLOYMENT READY"
  exit 0
  
elif [ "$STATUS" = "Skipped" ] && [ "${COMPONENT_FAIL_COUNT}" -eq 0 ] && [ "${TEST_FAIL_COUNT}" -eq 0 ]; then
  echo "✅ Validation: SKIPPED (no changes)"
  echo "✅ All quality gates met"
  echo ""
  echo "🎉 PIPELINE SUCCESSFUL"
  exit 0
  
elif [ "${COMPONENT_FAIL_COUNT}" -gt 0 ] || [ "${TEST_FAIL_COUNT}" -gt 0 ]; then
  echo "❌ Validation: FAILED"
  echo "   • Component Failures: ${COMPONENT_FAIL_COUNT}"
  echo "   • Test Failures: ${TEST_FAIL_COUNT}"
  echo ""
  echo "💥 QUALITY GATES FAILED - Fix issues before deploying"
  exit 1
  
elif [ "$STATUS" != "Succeeded" ] && [ "$COVERAGE" -lt "${COVERAGE_THRESHOLD}" ] && [ "$STATUS" != "Skipped" ]; then
  echo "❌ Validation: FAILED"
  echo "   • Coverage: ${COVERAGE}% (required: ${COVERAGE_THRESHOLD}%)"
  echo ""
  echo "💥 QUALITY GATES FAILED - Increase test coverage"
  exit 1
  
else
  echo "✅ Validation: PASSED"
  echo "✅ All quality gates met"
  echo ""
  echo "🎉 DEPLOYMENT READY"
  exit 0
fi
