#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/run_phantom_against.sh path/to/Cookiejar
#
# Example:
#   ./scripts/run_phantom_against.sh plugins/Cookiejar
#
# Requirements:
# - PHP CLI (7.4+ or 8.x)
# - composer
# - (optional) semgrep in PATH for semgrep checks
# - (optional) phpstan installed via composer (vendor/bin/phpstan)
#
# What it does:
# - prepares artifacts dir
# - ensures composer allow-plugins for phpcs installer
# - composer install (vendor/bin/phpcs, phpstan etc)
# - run PHPCS (WPCS) -> artifacts/phpcs.json
# - run PHPCompatibility via PHPCS -> artifacts/phpcompat.json
# - run Semgrep (if installed) -> artifacts/semgrep.json
# - run PHPStan (if installed) -> artifacts/phpstan.json
# - run phantom-ai compliance handler -> artifacts/phantom-report.json
# - run phantom-ai auto-resolve in dry-run -> artifacts/auto-resolve-report.json + artifacts/patches/*.diff
# - uploads nothing (local), prints artifact locations

TARGET="${1:-.}"
ARTIFACTS_DIR="${2:-artifacts}"

echo "Target path: ${TARGET}"
echo "Artifacts dir: ${ARTIFACTS_DIR}"

# Ensure artifacts dirs
mkdir -p "${ARTIFACTS_DIR}"
mkdir -p "${ARTIFACTS_DIR}/patches"

# Allow PHPCS installer plugin for composer (non-persistent in CI it's ok; local will write config)
composer --version 2>/dev/null || { echo "composer not found; please install composer and re-run"; exit 2; }
composer config --no-plugins allow-plugins.dealerdirect/phpcodesniffer-composer-installer true || true

# Install composer dependencies
echo "Running composer install (this may take a while)..."
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-interaction --no-progress --prefer-dist

# Run PHPCS (WPCS) -> artifacts/phpcs.json
if [ -x vendor/bin/phpcs ]; then
  echo "Running PHPCS (WPCS)..."
  vendor/bin/phpcs --standard=WordPress --report=json --report-file="${ARTIFACTS_DIR}/phpcs.json" "${TARGET}" || true
else
  echo "vendor/bin/phpcs not found; writing placeholder ${ARTIFACTS_DIR}/phpcs.json"
  echo '{}' > "${ARTIFACTS_DIR}/phpcs.json"
fi

# Run PHPCompatibility via PHPCS -> artifacts/phpcompat.json
if [ -x vendor/bin/phpcs ]; then
  echo "Running PHPCompatibility checks via PHPCS..."
  # adjust testVersion as needed
  vendor/bin/phpcs --standard=PHPCompatibility --runtime-set testVersion 7.4-8.1 --report=json --report-file="${ARTIFACTS_DIR}/phpcompat.json" "${TARGET}" || true
else
  echo '{}' > "${ARTIFACTS_DIR}/phpcompat.json"
fi

# Run Semgrep if available
if command -v semgrep >/dev/null 2>&1; then
  echo "Running Semgrep..."
  semgrep --config p/ci --json --output "${ARTIFACTS_DIR}/semgrep.json" "${TARGET}" || true
else
  echo "semgrep not found in PATH; skipping. Writing placeholder ${ARTIFACTS_DIR}/semgrep.json"
  echo '{}' > "${ARTIFACTS_DIR}/semgrep.json"
fi

# Run PHPStan if available in vendor
if [ -x vendor/bin/phpstan ]; then
  echo "Running PHPStan..."
  vendor/bin/phpstan analyse --error-format=json -l 5 --no-progress --no-interaction "${TARGET}" > "${ARTIFACTS_DIR}/phpstan.json" || true
else
  echo "vendor/bin/phpstan not found; writing placeholder ${ARTIFACTS_DIR}/phpstan.json"
  echo '{}' > "${ARTIFACTS_DIR}/phpstan.json"
fi

# Post-process with phantom-ai compliance handler if present
if [ -f phantom-ai/compliance-warnings/src/Handler.php ]; then
  echo "Running phantom-ai compliance handler..."
  php phantom-ai/compliance-warnings/src/Handler.php --input "${ARTIFACTS_DIR}" --output "${ARTIFACTS_DIR}" || true
else
  echo "phantom-ai/compliance-warnings handler missing; skipping."
fi

# Run structure-preserving auto-resolve (dry-run) if present
if [ -f phantom-ai/structure-preserving-auto-resolve/src/AutoResolve.php ]; then
  echo "Running phantom-ai auto-resolve (dry-run)..."
  php phantom-ai/structure-preserving-auto-resolve/src/AutoResolve.php --root "${TARGET}" --output "${ARTIFACTS_DIR}" --dry-run || true
else
  echo "phantom-ai auto-resolve worker missing; skipping."
fi

echo "Run complete. Artifacts produced (if tools present):"
ls -la "${ARTIFACTS_DIR}" || true
echo
echo "Important artifact files you can now review or share:"
echo " - ${ARTIFACTS_DIR}/phantom-report.json"
echo " - ${ARTIFACTS_DIR}/phpcs.json"
echo " - ${ARTIFACTS_DIR}/phpcompat.json"
echo " - ${ARTIFACTS_DIR}/semgrep.json"
echo " - ${ARTIFACTS_DIR}/phpstan.json"
echo " - ${ARTIFACTS_DIR}/auto-resolve-report.json"
echo " - ${ARTIFACTS_DIR}/patches/*.diff"
