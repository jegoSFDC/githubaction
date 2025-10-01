#!/bin/bash
# ==============================================================================
# Intelligent Test Mapping Script
# ==============================================================================
# Analyzes deployment delta package to identify changed Apex classes and
# intelligently maps them to relevant test classes for targeted testing.
#
# Algorithm:
#   1. Extract Apex classes from delta package.xml
#   2. Classify classes as production vs test classes using @isTest annotation
#   3. Map production classes to related test classes using naming patterns
#   4. Generate test execution strategy with fallback options
#
# Test Discovery Patterns:
#   - Test class naming conventions (ClassNameTest, ClassName_Test)
#   - Direct instantiation patterns (new ClassName())
#   - Method invocation patterns (ClassName.methodName())
#   - Static method calls (ClassName.staticMethod())
#
# Output:
#   - JSON mapping file for test relationships
#   - Environment variables for downstream pipeline steps
# ==============================================================================

set -euo pipefail

echo ""
echo "🚀 STAGE 5: INTELLIGENT TEST EXECUTION"
echo "===================================="
echo "🧠 Analyzing delta package for intelligent test mapping..."

# Initialize tracking variables
TESTS_IN_DELTA=""
PROD_CLASSES=""
RELATED_TESTS=""

# Function to classify Apex classes and map tests
classify_and_map_tests() {
  local apex_classes="$1"

  echo ""
  echo "📋 Processing Apex classes: $apex_classes"

  for class in $apex_classes; do
    local file_path
    file_path=$(find delta/force-app force-app -path "*/classes/${class}.cls" 2>/dev/null | head -n1)

    if [ -z "$file_path" ]; then
      echo "  ⚠️  ${class}: Source file not found - treating as production class"
      PROD_CLASSES="$PROD_CLASSES $class"
      continue
    fi

    # Check if class is a test class using @isTest annotation
    if grep -qi "@isTest" "$file_path"; then
      echo "  ✅ ${class}: Identified as test class"
      TESTS_IN_DELTA="$TESTS_IN_DELTA $class"
    else
      echo "  ✅ ${class}: Identified as production class"
      PROD_CLASSES="$PROD_CLASSES $class"
    fi
  done

  # Normalize class lists
  TESTS_IN_DELTA=$(echo "$TESTS_IN_DELTA" | xargs -n1 2>/dev/null | sort -u | xargs || echo "")
  PROD_CLASSES=$(echo "$PROD_CLASSES" | xargs -n1 2>/dev/null | sort -u | xargs || echo "")

  echo ""
  echo "📊 Classification Results:"
  echo "  Production classes: ${PROD_CLASSES:-none}"
  echo "  Test classes: ${TESTS_IN_DELTA:-none}"
}

# Function to map production classes to related test classes
map_production_to_tests() {
  echo ""
  echo "🔗 Mapping production classes to test classes..."

  # Initialize JSON output for test mapping
  echo "📄 Generating test mapping JSON file..."
  echo "{" > reports/test-mapping.json
  echo '  "mapping": [' >> reports/test-mapping.json
  local separator=""

  if [ -n "$PROD_CLASSES" ] && [ -n "$TESTS_IN_DELTA" ]; then
    echo "🔍 Analyzing relationships between production and test classes..."
    for prod_class in $PROD_CLASSES; do
      local found_tests=""

      for test_class in $TESTS_IN_DELTA; do
        local test_file
        test_file=$(find delta/force-app force-app -path "*/classes/${test_class}.cls" 2>/dev/null | head -n1)

        if [ -n "$test_file" ]; then
          # Look for patterns that suggest this test covers the production class
          if grep -qiE "(new[[:space:]]+${prod_class}\b|${prod_class}\.[A-Za-z_]|${prod_class}[[:space:]]*\()" "$test_file"; then
            found_tests="$found_tests $test_class"
          fi
        fi
      done

      # Normalize found test classes
      found_tests=$(echo "$found_tests" | xargs -n1 2>/dev/null | sort -u | xargs || echo "")

      if [ -n "$found_tests" ]; then
        RELATED_TESTS="$RELATED_TESTS $found_tests"
      fi

      # Generate JSON mapping entry
      if [ -n "$found_tests" ]; then
        local json_tests
        json_tests=$(echo "$found_tests" | xargs -n1 | sed 's/^/"/;s/$/"/' | paste -sd, -)
      else
        local json_tests=""
      fi

      echo "$separator    {\"apexClass\": \"${prod_class}\", \"tests\": [${json_tests}]}" >> reports/test-mapping.json
      separator=","
    done
  fi

  echo '  ]' >> reports/test-mapping.json
  echo '}' >> reports/test-mapping.json

  # Normalize related tests list
  RELATED_TESTS=$(echo "$RELATED_TESTS" | xargs -n1 2>/dev/null | sort -u | xargs || echo "")

  echo ""
  echo "✅ Test mapping completed"
  echo "📋 Tests identified for execution: ${RELATED_TESTS:-none (will use RunLocalTests fallback)}"
}

# Main execution flow
main() {
  # Extract Apex classes from delta package
  if [ -f delta/package/package.xml ]; then
    echo "📦 Extracting Apex classes from delta package.xml..."

    # Use xpath-like parsing to extract class names from package.xml
    DELTA_APEX_CLASSES=$(grep -oP '(?<=<members>).*?(?=</members>)' delta/package/package.xml | grep -v '^$' | tr '\n' ' ' | sed 's/ *$//')
    echo "📋 Apex classes in delta: ${DELTA_APEX_CLASSES:-none}"
  else
    echo "⚠️  No delta/package/package.xml found"
    DELTA_APEX_CLASSES=""
  fi

  # Find actual .cls files in delta
  APEX_CLASSES=$(find delta/force-app/main/default/classes -name '*.cls' -maxdepth 1 -exec basename {} .cls \; | tr '\n' ' ' | sed 's/ *$//')

  if [ -n "$APEX_CLASSES" ]; then
    classify_and_map_tests "$APEX_CLASSES"
    map_production_to_tests

    # Export environment variables for downstream steps
    echo "APEX_CLASSES=$APEX_CLASSES" >> "$GITHUB_ENV"
    echo "DELTA_APEX_CLASSES=$DELTA_APEX_CLASSES" >> "$GITHUB_ENV"
    echo "TESTS_IN_DELTA=$TESTS_IN_DELTA" >> "$GITHUB_ENV"
    echo "RELATED_TESTS=$RELATED_TESTS" >> "$GITHUB_ENV"

    echo ""
    echo "📈 Test mapping summary:"
    echo "  • Production classes requiring tests: $(echo "$PROD_CLASSES" | wc -w)"
    echo "  • Test classes available in delta: $(echo "$TESTS_IN_DELTA" | wc -w)"
    echo "  • Related test classes identified: $(echo "$RELATED_TESTS" | wc -w)"

  else
    echo "ℹ️  No Apex classes found in delta - no test mapping required"
  fi

  echo ""
  echo "✅ STAGE 5 COMPLETED: Test mapping analysis finished"
  echo "==============================================="
}

# Execute main function
main
