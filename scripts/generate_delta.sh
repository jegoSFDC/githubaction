#!/bin/bash
# ==============================================================================
# Delta Package Generation Script
# ==============================================================================
# Generates deployment delta package using sfdx-git-delta plugin to identify
# changes between source and target branches for incremental deployments.
#
# Process Flow:
#   1. Configure git workspace safety settings
#   2. Fetch target branch for comparison baseline
#   3. Generate delta package with changed metadata
#   4. Validate delta package structure and contents
#
# Output Artifacts:
#   - delta/package.xml: Primary deployment manifest
#   - delta/force-app/: Source metadata for deployment
#   - Destructive changes manifest (if applicable)
# ==============================================================================

set -euo pipefail

echo ""
echo "🚀 STAGE 3: DELTA PACKAGE GENERATION"
echo "======================================"
echo "🔄 Generating deployment delta package..."

# Ensure output directories exist
echo "📁 Creating output directories..."
mkdir -p delta reports

# Configure git safety for workspace operations
echo "🔧 Configuring git workspace safety..."
git config --global --add safe.directory "$GITHUB_WORKSPACE"

# Fetch target branch for delta comparison
TARGET_BRANCH="${TARGET_BRANCH:-main}"
echo "📥 Fetching target branch: $TARGET_BRANCH"
git fetch origin "$TARGET_BRANCH" --quiet

echo "📊 Generating delta from origin/$TARGET_BRANCH to HEAD"

# Generate delta package using sfdx-git-delta plugin
echo "⚙️  Executing sfdx-git-delta plugin..."
if sf sgd source delta \
  --to HEAD \
  --from "origin/$TARGET_BRANCH" \
  --output delta \
  --generate-delta >/dev/null 2>&1; then

  echo "✅ Delta generation completed successfully"
else
  echo "❌ Delta generation failed - check git history and branch availability"
  exit 1
fi

# Validate and display delta package analysis
echo ""
echo "📋 Delta Package Analysis:"
echo "=========================="

# Check for delta files
DELTA_COUNT=$(find delta -type f | wc -l)
echo "📁 Total files in delta: $DELTA_COUNT"

if [ -f delta/package/package.xml ]; then
  echo ""
  echo "📦 Package.xml Preview (first 20 lines):"
  sed -n '1,20p' delta/package/package.xml

  echo ""
  echo "🔍 Destructive Changes Analysis:"
  if find delta -name "destructiveChanges*.xml" -exec echo "  Found: {}" \; -exec sed -n '1,20p' {} \; | head -10; then
    echo "  ⚠️  Destructive changes detected in deployment package"
  else
    echo "  ✅ No destructive changes found"
  fi
else
  echo ""
  echo "⚠️  Warning: No package.xml found in delta package"
fi

echo ""
echo "📊 Delta generation summary:"
ls -la delta || echo "No delta directory found"

echo ""
echo "✅ STAGE 3 COMPLETED: Delta package generated successfully"
echo "=================================================="
