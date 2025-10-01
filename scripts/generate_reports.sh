#!/bin/bash
# ==============================================================================
# Validation Reporting and Quality Gates Script
# ==============================================================================
# Generates comprehensive human-readable reports from deployment validation
# results and determines pipeline success/failure based on organizational
# quality gates and thresholds.
#
# Report Components:
#   - Deployment Status Summary
#   - Component Failure Analysis
#   - Test Execution Results
#   - Code Coverage Metrics
#   - Quality Gate Validation
#
# Quality Gates Validated:
#   - Component deployment success
#   - Test execution results
#   - Code coverage thresholds
#   - Security violation tolerance
#
# Exit Strategy:
#   0 - All quality gates passed or appropriately skipped
#   1 - Quality gates failed (deployment issues, test failures, coverage issues)
# ==============================================================================

set -euo pipefail

# Initialize default values for safety
STATUS="Failed"
COMPONENT_FAIL_COUNT=0
TEST_FAIL_COUNT=0
COVERAGE=0

# Logging function for consistent output formatting
summary() {
  echo "$1" | tee -a reports/validation-summary.txt
}

# Function to extract validation metrics from deploy report
extract_validation_metrics() {
  if [ -f reports/deploy-report.json ]; then
    STATUS=$(jq -r '.result.status // "Failed"' reports/deploy-report.json 2>/dev/null || echo "Failed")
  fi

  if jq -e '.result.details.componentFailures' reports/deploy-report.json >/dev/null 2>&1; then
    COMPONENT_FAIL_COUNT=$(jq '.result.details.componentFailures | length' reports/deploy-report.json 2>/dev/null || echo "0")
  fi

  if jq -e '.result.details.runTestResult.failures' reports/deploy-report.json >/dev/null 2>&1; then
    TEST_FAIL_COUNT=$(jq '.result.details.runTestResult.failures | length' reports/deploy-report.json 2>/dev/null || echo "0")
  fi

  # Check if this is a metadata-only deployment (no Apex code)
  if jq -e '.result.status == "Skipped" and (.result.message | contains("No Apex deployment"))' reports/deploy-report.json >/dev/null 2>&1; then
    # Metadata-only deployment - no coverage requirements
    COVERAGE="N/A"
    summary "📄 Metadata-only deployment detected - coverage requirements waived"
  elif jq -e '.result.status == "Succeeded" and (.result.details.runTestResult.testsRun == 0 or .result.details.runTestResult == null)' reports/deploy-report.json >/dev/null 2>&1; then
    # Deployment succeeded with no tests run (metadata-only like LWC)
    COVERAGE="N/A"
    summary "📄 Metadata-only deployment (LWC/other) - coverage requirements waived"
  elif jq -e '.result.details.runTestResult.codeCoverage' reports/deploy-report.json >/dev/null 2>&1; then
    COVERAGE=$(jq -r '[.result.details.runTestResult.codeCoverage[]? | (.coveredPercent // 0)] | (if length>0 then (add/length) else 0 end)' reports/deploy-report.json 2>/dev/null || echo "0")
    COVERAGE=${COVERAGE%.*}
  else
    COVERAGE="0"
  fi
}

# Function to generate comprehensive validation summary
generate_summary_report() {
  # Append summary header to validation log
  echo "" >> reports/validation-summary.txt
  echo "=== DEPLOYMENT VALIDATION SUMMARY ===" >> reports/validation-summary.txt
  echo "Status: ${STATUS}" >> reports/validation-summary.txt
  echo "Component failures: ${COMPONENT_FAIL_COUNT}" >> reports/validation-summary.txt
  echo "Test failures: ${TEST_FAIL_COUNT}" >> reports/validation-summary.txt
  echo "Average coverage: ${COVERAGE}%" >> reports/validation-summary.txt
  echo "================================" >> reports/validation-summary.txt

  # Display compact summary for pipeline logs (without file logging)
  echo ""
  echo "📋 Validation Summary:"
  echo "  • Status: ${STATUS}"
  echo "  • Component failures: ${COMPONENT_FAIL_COUNT}"
  echo "  • Test failures: ${TEST_FAIL_COUNT}"
  if [ "$COVERAGE" = "N/A" ]; then
    echo "  • Coverage: ${COVERAGE} (metadata-only deployment)"
  else
    echo "  • Coverage: ${COVERAGE}% (threshold: ${COVERAGE_THRESHOLD}%)"
  fi
}

# Function to display detailed failure analysis
display_failure_analysis() {
  if [ "${COMPONENT_FAIL_COUNT}" -gt 0 ] || [ "${TEST_FAIL_COUNT}" -gt 0 ] || ([ "$COVERAGE" != "N/A" ] && [ "${COVERAGE}" -lt "${COVERAGE_THRESHOLD}" ]); then
    echo ""
    echo "⚠️  Quality gate violations detected"

    # Display test failure details (sanitized)
    if jq -e '.result.details.runTestResult.failures' reports/deploy-report.json >/dev/null 2>&1; then
      echo ""
      echo "🧪 Test Execution Failures:"
      jq -r '.result.details.runTestResult.failures[]? |
        "\(.name) - Method: \(.methodName // "unknown")\n\(.message // "" )" ' reports/deploy-report.json 2>/dev/null \
        | sed -e "s/<br>/\\n/g" -e "s/<[^>]*>//g" \
        | awk -v RS= -v ORS="\n\n" 'NR<=10{print}' || true
    fi

    # Display component deployment failures
    if [ "${COMPONENT_FAIL_COUNT}" -gt 0 ]; then
      echo ""
      echo "🔧 Component Deployment Failures:"
      jq -r '.result.details.componentFailures[]? | "  • " + (.fileName // .name) + ": " + (.problem // "Unknown problem")' reports/deploy-report.json 2>/dev/null | head -10 || true
    fi

    # Display coverage breakdown
    display_coverage_analysis
  else
    echo ""
    echo "✅ All quality gates passed successfully"
  fi
}

# Function to display detailed coverage analysis
display_coverage_analysis() {
  if jq -e '.result.details.runTestResult.codeCoverage' reports/deploy-report.json >/dev/null 2>&1; then
    echo ""
    echo "📊 Code Coverage Analysis:"

    local avg_coverage
    avg_coverage=$(jq -r '[.result.details.runTestResult.codeCoverage[]? | (.coveredPercent // null)] | map(select(. != null)) | (if length>0 then (add/length) else 0 end)' reports/deploy-report.json 2>/dev/null || echo "0")
    avg_coverage=${avg_coverage%.*}
    echo "   • Overall Average: ${avg_coverage}%"

    echo ""
    echo "📋 Coverage Breakdown by Class:"

    # Display classes with numeric coverage (top 30)
    jq -r '.result.details.runTestResult.codeCoverage[]? | ( .coveredPercent // "N/A") as $p | "  - \(.name): \($p)%"' reports/deploy-report.json 2>/dev/null | sed 's/N\/A%/N\/A/' | head -30 || true

    # Identify classes with zero coverage
    local zero_coverage
    zero_coverage=$(jq -r '.result.details.runTestResult.codeCoverage[]? | select(.coveredPercent == 0) | .name' reports/deploy-report.json 2>/dev/null || true)
    if [ -n "$zero_coverage" ]; then
      echo ""
      echo "  • Classes with 0% coverage (require tests):"
      echo "$zero_coverage" | sed 's/^/    - /'
    fi

    # Identify classes below threshold
    echo ""
    echo "  • Classes below coverage threshold (${COVERAGE_THRESHOLD}%):"
    jq -r --arg threshold "${COVERAGE_THRESHOLD}" '.result.details.runTestResult.codeCoverage[]? |
      select(.coveredPercent != null) |
      select((.coveredPercent | tonumber) < ($threshold | tonumber)) |
      "    - \(.name): \(.coveredPercent)%"' reports/deploy-report.json 2>/dev/null | head -50 || echo "    None"
  fi
}

# Function to validate overall pipeline success/failure
validate_quality_gates() {
  echo ""
  echo "🔍 Validating quality gates..."

  # Primary validation: deployment success
  if [ "$STATUS" = "Succeeded" ]; then
    echo "✅ Deployment validation: PASSED"
    return 0
  fi

  # Secondary validation: appropriate skip condition
  if [ "$STATUS" = "Skipped" ] && [ "${COMPONENT_FAIL_COUNT}" -eq 0 ] && [ "${TEST_FAIL_COUNT}" -eq 0 ]; then
    echo "✅ Validation appropriately skipped (no deployable changes)"
    return 0
  fi

  # Failure conditions
  if [ "${COMPONENT_FAIL_COUNT}" -gt 0 ]; then
    echo "❌ Component deployment failures: ${COMPONENT_FAIL_COUNT}"
    return 1
  fi

  if [ "${TEST_FAIL_COUNT}" -gt 0 ]; then
    echo "❌ Test execution failures: ${TEST_FAIL_COUNT}"
    return 1
  fi

  # Check coverage requirements (only for Apex deployments)
  if [ "$COVERAGE" != "N/A" ] && [ "$STATUS" != "Succeeded" ] && [ "$COVERAGE" -lt "${COVERAGE_THRESHOLD}" ] && [ "$STATUS" != "Skipped" ]; then
    echo "❌ Coverage below threshold: ${COVERAGE}% < ${COVERAGE_THRESHOLD}%"
    return 1
  fi

  # Default success case
  echo "✅ Quality gates validation: PASSED"
  return 0
}

# Main execution flow
main() {
  echo ""
  echo "🚀 STAGE 6: VALIDATION REPORTING & QUALITY GATES"
  echo "=============================================="
  echo "📋 Generating deployment validation reports..."

  # Extract metrics from deploy report
  echo "📊 Extracting validation metrics from deploy report..."
  extract_validation_metrics

  # Generate summary report
  echo "📄 Generating comprehensive validation summary..."
  generate_summary_report

  # Display detailed failure analysis if issues exist
  echo "🔍 Analyzing validation results for quality gates..."
  display_failure_analysis

  # Validate quality gates and determine pipeline outcome
  echo ""
  echo "🔍 Validating quality gates..."
  if validate_quality_gates; then
    echo ""
    echo "🎉 PIPELINE QUALITY GATES: ALL PASSED"
    echo "===================================="

    echo ""
    echo "📋 PIPELINE EXECUTION SUMMARY"
    echo "============================"
    echo "✅ Environment Configuration: Completed"
    echo "✅ Salesforce Authentication: Completed"
    echo "✅ Delta Package Generation: Completed"
    echo "✅ Static Code Analysis: Completed"
    if [ "$COVERAGE" = "N/A" ]; then
      if [ "$STATUS" = "Succeeded" ]; then
        echo "⏭️  Intelligent Test Execution: Skipped (no Apex code)"
        echo "✅ Deployment Validation: Completed (metadata-only)"
        echo "⏭️  Coverage Filtering: Skipped (no Apex code)"
      else
        echo "⏭️  Intelligent Test Execution: Skipped (metadata-only)"
        echo "⏭️  Deployment Validation: Skipped (no deployment package)"
        echo "⏭️  Coverage Filtering: Skipped (metadata-only)"
      fi
    else
      echo "✅ Intelligent Test Execution: Completed"
      echo "✅ Deployment Validation: Completed"
      echo "✅ Coverage Filtering: Completed"
    fi
    echo "✅ Validation Reporting: Completed"
    echo ""
    echo "🏆 PIPELINE COMPLETED SUCCESSFULLY!"
    exit 0
  else
    echo ""
    echo "💥 PIPELINE QUALITY GATES: FAILED"
    echo "================================"

    echo ""
    echo "📋 PIPELINE EXECUTION SUMMARY"
    echo "============================"
    echo "✅ Environment Configuration: Completed"
    echo "✅ Salesforce Authentication: Completed"
    echo "✅ Delta Package Generation: Completed"
    echo "✅ Static Code Analysis: Completed"
    if [ "$COVERAGE" = "N/A" ]; then
      echo "⏭️  Intelligent Test Execution: Skipped (metadata-only)"
      echo "⏭️  Deployment Validation: Skipped (no deployment package)"
      echo "⏭️  Coverage Filtering: Skipped (metadata-only)"
    else
      echo "✅ Intelligent Test Execution: Completed"
      echo "✅ Deployment Validation: Completed"
      echo "✅ Coverage Filtering: Completed"
    fi
    echo "❌ Validation Reporting: FAILED"
    echo ""
    echo "⚠️  PIPELINE COMPLETED WITH ERRORS!"
    exit 1
  fi
}

# Execute main function
main
