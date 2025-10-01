#!/bin/bash
# ==============================================================================
# Final Validation Reporting and Quality Gate Enforcement
# ==============================================================================
# Generates comprehensive validation reports and determines pipeline success/failure
# based on deployment validation results and organizational quality standards.
#
# Quality Gates:
#   - Component deployment success
#   - Test execution results
#   - Code coverage thresholds
#   - No component or test failures
#
# Exit Codes:
#   0 - All quality gates passed or appropriately skipped
#   1 - Quality gates failed
# ==============================================================================

set -euo pipefail

echo ""
echo "🚀 STAGE 6: VALIDATION REPORTING & QUALITY GATES"
echo "=============================================="
echo "📋 Analyzing deployment validation results..."

# Initialize default values
STATUS="Failed"
COMPONENT_FAIL_COUNT=0
TEST_FAIL_COUNT=0
COVERAGE=0

# Extract metrics from deploy report
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

# Write summary file
echo "" >> reports/validation-summary.txt
echo "=== DEPLOY VALIDATION SUMMARY ===" >> reports/validation-summary.txt
echo "Status: ${STATUS}" >> reports/validation-summary.txt
echo "Component failures: ${COMPONENT_FAIL_COUNT}" >> reports/validation-summary.txt
echo "Test failures: ${TEST_FAIL_COUNT}" >> reports/validation-summary.txt
echo "Average coverage: ${COVERAGE}%" >> reports/validation-summary.txt
echo "================================" >> reports/validation-summary.txt

# Display summary in pipeline logs
echo ""
echo "📊 VALIDATION SUMMARY"
echo "===================="
echo "  • Status: ${STATUS}"
echo "  • Component failures: ${COMPONENT_FAIL_COUNT}"
echo "  • Test failures: ${TEST_FAIL_COUNT}"
echo "  • Coverage: ${COVERAGE}% (threshold: ${COVERAGE_THRESHOLD}%)"

# Display detailed failure information if issues exist
if [ "${COMPONENT_FAIL_COUNT}" -gt 0 ] || [ "${TEST_FAIL_COUNT}" -gt 0 ] || [ "${COVERAGE}" -lt "${COVERAGE_THRESHOLD}" ]; then
  echo ""
  echo "⚠️  QUALITY GATE VIOLATIONS DETECTED"
  echo "===================================="

  # Display test failures
  if jq -e '.result.details.runTestResult.failures' reports/deploy-report.json >/dev/null 2>&1; then
    echo ""
    echo "🧪 Test Failures:"
    jq -r '.result.details.runTestResult.failures[]? |
      "\(.name) - Method: \(.methodName // "unknown")\n\(.message // "" )" ' reports/deploy-report.json 2>/dev/null \
      | sed -e "s/<br>/\\n/g" -e "s/<[^>]*>//g" \
      | awk -v RS= -v ORS="\n\n" 'NR<=10{print}' || true
  fi

  # Display component failures
  if [ "${COMPONENT_FAIL_COUNT}" -gt 0 ]; then
    echo ""
    echo "🔧 Component Failures:"
    jq -r '.result.details.componentFailures[]? | "  • " + (.fileName // .name) + ": " + (.problem // "Unknown problem")' reports/deploy-report.json 2>/dev/null | head -10 || true
  fi

  # Display coverage breakdown
  if jq -e '.result.details.runTestResult.codeCoverage' reports/deploy-report.json >/dev/null 2>&1; then
    echo ""
    echo "📊 Coverage Breakdown:"
    echo "====================="
    
    AVG=$(jq -r '[.result.details.runTestResult.codeCoverage[]? | (.coveredPercent // null)] | map(select(. != null)) | (if length>0 then (add/length) else 0 end)' reports/deploy-report.json 2>/dev/null || echo "0")
    AVG=${AVG%.*}
    echo "  • Overall Average: ${AVG}%"
    echo ""
    
    echo "  Classes (showing top 30):"
    jq -r '.result.details.runTestResult.codeCoverage[]? | ( .coveredPercent // "N/A") as $p | "    - \(.name): \($p)%"' reports/deploy-report.json 2>/dev/null | sed 's/N\/A%/N\/A/' | head -30 || true
    
    # Classes with 0% coverage
    ZERO_LIST=$(jq -r '.result.details.runTestResult.codeCoverage[]? | select(.coveredPercent == 0) | .name' reports/deploy-report.json 2>/dev/null || true)
    if [ -n "$ZERO_LIST" ]; then
      echo ""
      echo "  ⚠️  Classes with 0% coverage:"
      echo "$ZERO_LIST" | sed 's/^/    - /'
    fi
    
    # Classes below threshold
    echo ""
    echo "  ⚠️  Classes below ${COVERAGE_THRESHOLD}% threshold:"
    jq -r --arg thr "${COVERAGE_THRESHOLD}" '.result.details.runTestResult.codeCoverage[]? |
      select(.coveredPercent != null) |
      select((.coveredPercent | tonumber) < ($thr | tonumber)) |
      "    - \(.name): \(.coveredPercent)%"' reports/deploy-report.json 2>/dev/null | head -50 || echo "    None"
  fi
fi

echo ""
echo "🔍 VALIDATING QUALITY GATES"
echo "==========================="

# Validate quality gates
if [ "$STATUS" = "Succeeded" ]; then
  echo "✅ Deployment validation: PASSED"
  echo "✅ Status: ${STATUS}, Coverage: ${COVERAGE}%"
  echo ""
  echo "🎉 ALL QUALITY GATES PASSED"
  exit 0
  
elif [ "$STATUS" = "Skipped" ] && [ "${COMPONENT_FAIL_COUNT}" -eq 0 ] && [ "${TEST_FAIL_COUNT}" -eq 0 ]; then
  echo "✅ Validation appropriately skipped (no deployable changes)"
  echo ""
  echo "🎉 ALL QUALITY GATES PASSED"
  exit 0
  
elif [ "${COMPONENT_FAIL_COUNT}" -gt 0 ] || [ "${TEST_FAIL_COUNT}" -gt 0 ]; then
  echo "❌ QUALITY GATES FAILED"
  echo "  • Component failures: ${COMPONENT_FAIL_COUNT}"
  echo "  • Test failures: ${TEST_FAIL_COUNT}"
  echo ""
  echo "💥 PIPELINE FAILED - See reports for details"
  exit 1
  
elif [ "$STATUS" != "Succeeded" ] && [ "$COVERAGE" -lt "${COVERAGE_THRESHOLD}" ] && [ "$STATUS" != "Skipped" ]; then
  echo "❌ QUALITY GATES FAILED"
  echo "  • Coverage: ${COVERAGE}% (threshold: ${COVERAGE_THRESHOLD}%)"
  echo "  • Status: ${STATUS}"
  echo ""
  echo "💥 PIPELINE FAILED - Coverage below threshold"
  exit 1
  
else
  echo "✅ Validation passed: status=${STATUS}, coverage=${COVERAGE}%"
  echo ""
  echo "🎉 ALL QUALITY GATES PASSED"
  exit 0
fi
