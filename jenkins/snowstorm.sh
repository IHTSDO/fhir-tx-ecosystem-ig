#!/usr/bin/env bash
# Manage a throwaway Elasticsearch + Snowstorm stack in Docker for the tx-ecosystem tests.
#
#   jenkins/snowstorm.sh build   Build the Snowstorm jar from $SNOWSTORM_SRC
#   jenkins/snowstorm.sh up      Start Elasticsearch and Snowstorm, wait until FHIR is ready
#   jenkins/snowstorm.sh load    Import tx-source/snomed as the SNOMED CT version the tests expect
#   jenkins/snowstorm.sh url     Print the host URL of the Snowstorm FHIR endpoint
#   jenkins/snowstorm.sh down    Save the Snowstorm log and remove the containers and network
#
# Environment:
#   TX_TESTS_PREFIX        Name prefix for containers and network (default txtests-local)
#   SNOWSTORM_SRC          Snowstorm source checkout (default snowstorm-src)
#   TESTS_ROOT             Directory holding tests/ and tx-source/ (default: this repository)
#   OUTPUT_DIR             Where logs are written (default test-results)
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX=$(printf '%s' "${TX_TESTS_PREFIX:-txtests-local}" | tr -c 'a-zA-Z0-9_.-' '-')
NETWORK="$PREFIX"
ES_CONTAINER="$PREFIX-es"
SNOWSTORM_CONTAINER="$PREFIX-snowstorm"
SNOWSTORM_SRC="${SNOWSTORM_SRC:-$REPO_ROOT/snowstorm-src}"
[[ -d "$SNOWSTORM_SRC" ]] && SNOWSTORM_SRC=$(cd "$SNOWSTORM_SRC" && pwd)
TESTS_ROOT=$(cd "${TESTS_ROOT:-$REPO_ROOT}" && pwd)
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/test-results}"
JAVA_IMAGE="amazoncorretto:25"
MAVEN_IMAGE="maven:3.9-amazoncorretto-25"

log() { echo "[snowstorm.sh] $*"; }
die() { echo "[snowstorm.sh] ERROR: $*" >&2; exit 1; }

snowstorm_url() {
    local port
    port=$(docker port "$SNOWSTORM_CONTAINER" 8080/tcp | head -1) || die "Snowstorm container $SNOWSTORM_CONTAINER is not running"
    echo "http://$port"
}

wait_for() {
    local description=$1 attempts=$2 container state
    shift 2
    for ((i = 1; i <= attempts; i++)); do
        if "$@" >/dev/null 2>&1; then
            log "$description is ready"
            return 0
        fi
        for container in "$ES_CONTAINER" "$SNOWSTORM_CONTAINER"; do
            state=$(docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' "$container" 2>/dev/null) || continue
            if [[ "$state" != running* ]]; then
                docker logs --tail 50 "$container" >&2 || true
                die "$container stopped while waiting for $description ($state)"
            fi
        done
        sleep 5
    done
    return 1
}

cmd_build() {
    [[ -f "$SNOWSTORM_SRC/pom.xml" ]] || die "No Snowstorm checkout at $SNOWSTORM_SRC"
    mkdir -p "$HOME/.m2"
    log "Building Snowstorm in $SNOWSTORM_SRC"
    # Run as the Jenkins user so the workspace stays cleanable, sharing its ~/.m2 (and any settings.xml).
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$SNOWSTORM_SRC":/src -w /src \
        -v "$HOME/.m2":/var/maven/.m2 \
        -e MAVEN_CONFIG=/var/maven/.m2 \
        "$MAVEN_IMAGE" \
        mvn -B -U -Duser.home=/var/maven -DskipTests -Ddependency-check.skip=true clean package
}

snowstorm_jar() {
    find "$SNOWSTORM_SRC/target" -maxdepth 1 -name 'snowstorm-*.jar' ! -name '*-sources.jar' ! -name '*-javadoc.jar' | head -1
}

elasticsearch_version() {
    sed -n 's|.*image: *docker.elastic.co/elasticsearch/elasticsearch:\([^ ]*\).*|\1|p' "$SNOWSTORM_SRC/docker-compose.yml" | head -1
}

cmd_up() {
    local jar es_version
    jar=$(snowstorm_jar)
    [[ -n "$jar" ]] || die "No Snowstorm jar in $SNOWSTORM_SRC/target - run '$0 build' first"
    es_version=$(elasticsearch_version)
    [[ -n "$es_version" ]] || die "Could not find the Elasticsearch image tag in $SNOWSTORM_SRC/docker-compose.yml"

    cmd_down >/dev/null 2>&1 || true
    docker network create "$NETWORK" >/dev/null

    log "Starting Elasticsearch $es_version"
    docker run -d --name "$ES_CONTAINER" --network "$NETWORK" --network-alias es \
        -e discovery.type=single-node \
        -e xpack.security.enabled=false \
        -e "ES_JAVA_OPTS=-Xms1g -Xmx1g" \
        "docker.elastic.co/elasticsearch/elasticsearch:$es_version" >/dev/null
    wait_for "Elasticsearch" 60 docker exec "$ES_CONTAINER" \
        curl -sf "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" \
        || die "Elasticsearch did not start"

    log "Starting Snowstorm from $(basename "$jar")"
    docker run -d --name "$SNOWSTORM_CONTAINER" --network "$NETWORK" --network-alias snowstorm \
        -p 127.0.0.1::8080 \
        -v "$jar":/app/snowstorm.jar:ro \
        "$JAVA_IMAGE" \
        java -Xms1g -Xmx2g \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -jar /app/snowstorm.jar \
        --elasticsearch.urls=http://es:9200 >/dev/null

    local url
    url=$(snowstorm_url)
    wait_for "Snowstorm at $url" 120 curl -sf "$url/fhir/metadata" \
        || { docker logs --tail 200 "$SNOWSTORM_CONTAINER" >&2; die "Snowstorm did not start"; }
}

# The SNOMED CT version the tests were written against (it differs between IG releases),
# e.g. http://snomed.info/xsct/900000000000207008/version/20250814
expected_snomed_version() {
    grep -rhoE 'http://snomed\.info/xsct/[0-9]+/version/[0-9]{8}' "$TESTS_ROOT/tests" \
        | sort | uniq -c | sort -rn | awk 'NR == 1 {print $2}'
}

cmd_load() {
    local url work import_location status version_uri module effective_date release_date version_on_import
    url=$(snowstorm_url)
    work=$(mktemp -d)
    trap 'rm -rf "$work"' RETURN

    version_uri=$(expected_snomed_version)
    [[ -n "$version_uri" ]] || die "No http://snomed.info/xsct/.../version/... URI found in $TESTS_ROOT/tests"
    module=$(echo "$version_uri" | cut -d/ -f5)
    effective_date=$(echo "$version_uri" | cut -d/ -f7)
    release_date=$(find "$TESTS_ROOT/tx-source/snomed" -name 'sct2_Concept_Snapshot_*.txt' | sed -E 's/.*_([0-9]{8})\.txt$/\1/' | head -1)
    # Versioning on import skips the MRCM rule rebuild, which fails on subsets that include MRCM refsets.
    # Older IG releases expect a version dated differently from the files, so it is created afterwards.
    if [[ "$release_date" == "$effective_date" ]]; then version_on_import=true; else version_on_import=false; fi

    log "Setting SNOMEDCT URI module to $module"
    curl -sf -X PUT "$url/codesystems/SNOMEDCT" -H 'Content-Type: application/json' \
        -d "{\"uriModuleId\":\"$module\"}" >/dev/null

    (cd "$TESTS_ROOT/tx-source" && python3 -m zipfile -c "$work/snomed.zip" snomed)

    log "Importing tx-source/snomed snapshot ($release_date)"
    import_location=$(curl -sf -D - -o /dev/null -X POST "$url/imports" -H 'Content-Type: application/json' \
        -d "{\"type\":\"SNAPSHOT\",\"branchPath\":\"MAIN\",\"createCodeSystemVersion\":$version_on_import,\"internalRelease\":true}" \
        | tr -d '\r' | sed -n 's/^[Ll]ocation: *//p')
    [[ -n "$import_location" ]] || die "Snowstorm did not return an import location"
    curl -sf -X POST "${import_location}/archive" -F "file=@$work/snomed.zip" >/dev/null

    for ((i = 1; i <= 120; i++)); do
        status=$(curl -sf "$import_location" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
        case "$status" in
            COMPLETED) break ;;
            FAILED) curl -s "$import_location" >&2; die "SNOMED import failed" ;;
        esac
        sleep 5
    done
    [[ "$status" == COMPLETED ]] || die "SNOMED import did not finish (last status: $status)"

    # An internal release makes Snowstorm publish the version under xsct rather than sct.
    if [[ "$version_on_import" == false ]]; then
        log "Creating internal release $effective_date"
        curl -sf -X POST "$url/codesystems/SNOMEDCT/versions" -H 'Content-Type: application/json' \
            -d "{\"effectiveDate\":$effective_date,\"description\":\"tx-ecosystem test subset\",\"internalRelease\":true}" >/dev/null \
            || die "Could not create SNOMEDCT version $effective_date"
    fi

    local total
    total=$(curl -s -G "$url/fhir/ValueSet/\$expand" --data-urlencode 'url=http://snomed.info/sct?fhir_vs' \
        --data-urlencode count=0 --data-urlencode "system-version=http://snomed.info/sct|$version_uri" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("expansion", {}).get("total", ""))')
    [[ -n "$total" ]] || die "Snowstorm cannot expand SNOMED CT version $version_uri"
    log "SNOMED CT $version_uri loaded ($total concepts)"
}

cmd_down() {
    if docker inspect "$SNOWSTORM_CONTAINER" >/dev/null 2>&1; then
        mkdir -p "$OUTPUT_DIR"
        docker logs "$SNOWSTORM_CONTAINER" > "$OUTPUT_DIR/snowstorm.log" 2>&1 || true
    fi
    docker rm -f "$SNOWSTORM_CONTAINER" "$ES_CONTAINER" >/dev/null 2>&1 || true
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
}

case "${1:-}" in
    build) cmd_build ;;
    up) cmd_up ;;
    load) cmd_load ;;
    url) snowstorm_url ;;
    down) cmd_down ;;
    *) echo "Usage: $0 build|up|load|url|down" >&2; exit 2 ;;
esac
