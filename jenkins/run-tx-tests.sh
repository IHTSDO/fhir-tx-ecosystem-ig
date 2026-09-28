#!/usr/bin/env bash
# Run the tx-ecosystem tests in $TESTS_ROOT/tests against the Snowstorm started by jenkins/snowstorm.sh.
#
# Environment:
#   TX_TESTS_PREFIX    Must match the value used for jenkins/snowstorm.sh (default txtests-local)
#   VALIDATOR_VERSION  hapifhir/org.hl7.fhir.core release tag, or "latest" (default 6.9.9)
#   TESTS_ROOT         Directory holding tests/ (default: this repository)
#   TX_EXTERNALS       Externals file under TESTS_ROOT (default tests/messages-ontoserver.csiro.au.json)
#   TX_MODES           Space-separated test modes run in addition to "general" (default "snomed flat")
#   TX_FILTER          Optional txTests -filter value
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX=$(printf '%s' "${TX_TESTS_PREFIX:-txtests-local}" | tr -c 'a-zA-Z0-9_.-' '-')
VALIDATOR_VERSION="${VALIDATOR_VERSION:-6.9.9}"
TESTS_ROOT=$(cd "${TESTS_ROOT:-$REPO_ROOT}" && pwd)
TX_EXTERNALS="${TX_EXTERNALS:-tests/messages-ontoserver.csiro.au.json}"
JAVA_IMAGE="amazoncorretto:25"
TOOLS_DIR="$REPO_ROOT/.tx-tests"
VALIDATOR_JAR="$TOOLS_DIR/validator_cli-$VALIDATOR_VERSION.jar"

cd "$REPO_ROOT"
mkdir -p "$TOOLS_DIR/home"

if [[ "$VALIDATOR_VERSION" == latest || ! -s "$VALIDATOR_JAR" ]]; then
    if [[ "$VALIDATOR_VERSION" == latest ]]; then
        download_url="https://github.com/hapifhir/org.hl7.fhir.core/releases/latest/download/validator_cli.jar"
    else
        download_url="https://github.com/hapifhir/org.hl7.fhir.core/releases/download/$VALIDATOR_VERSION/validator_cli.jar"
    fi
    echo "[run-tx-tests.sh] Downloading $download_url"
    curl -fsSL --retry 3 -o "$VALIDATOR_JAR.part" "$download_url"
    mv "$VALIDATOR_JAR.part" "$VALIDATOR_JAR"
fi

# The validator's SSRF protection blocks plain-http/private servers unless fhir-settings.json allows them.
cat > "$TOOLS_DIR/fhir-settings.json" <<'JSON'
{
  "servers": [
    {
      "url": "http://snowstorm:8080/fhir",
      "type": "fhir",
      "authenticationType": "none",
      "allowHttp": true,
      "allowPrivateNetwork": true
    }
  ]
}
JSON

rm -rf test-results/actual test-results/expected test-results/report.json test-results/test-results.json \
    test-results/junit.xml test-results/baseline-passing.txt

args=(txTests -tx http://snowstorm:8080/fhir -externals "/tests-root/$TX_EXTERNALS" -output test-results -test-version /tests-root/tests)
for mode in ${TX_MODES-snomed flat}; do args+=(-mode "$mode"); done
[[ -n "${TX_FILTER:-}" ]] && args+=(-filter "$TX_FILTER")

# txTests exits non-zero whenever any test fails; regressions are judged by check-regressions.py instead.
docker run --rm \
    --network "$PREFIX" \
    --user "$(id -u):$(id -g)" \
    -v "$REPO_ROOT":/work -w /work \
    -v "$TESTS_ROOT":/tests-root:ro \
    "$JAVA_IMAGE" \
    java -Duser.home=/work/.tx-tests/home -Dfhir.settings.path=/work/.tx-tests/fhir-settings.json -jar "/work/.tx-tests/$(basename "$VALIDATOR_JAR")" "${args[@]}" \
    || true

[[ -s test-results/report.json ]] || { echo "[run-tx-tests.sh] ERROR: txTests did not produce test-results/report.json" >&2; exit 1; }
