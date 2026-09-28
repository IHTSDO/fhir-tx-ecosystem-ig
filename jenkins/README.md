# Snowstorm tx-ecosystem regression job

The `Jenkinsfile` at the repository root does the following:

1. Builds Snowstorm and runs it against a throwaway Elasticsearch in Docker.
2. Takes `tests/` and `tx-source/` from the IG release named by `TESTS_REF` (default `1.9.1`).
3. Loads the `tx-source/snomed` subset as the SNOMED CT version those tests expect. The load
   step reads that version from the tests: for `1.9.1` it is
   `http://snomed.info/xsct/900000000000207008/version/20250814`.
4. Runs the tests (modes `general`, `snomed` and `flat`; `flat` because Snowstorm returns non-hierarchical expansions) with the HL7 validator's `txTests` command.
5. Fails the build if a test listed in the baseline for that `TESTS_REF` and validator,
   `baselines/<TESTS_REF>/validator-<version>.txt`, no longer passes.

Many tests do not pass on Snowstorm yet, so they are not treated as failures. In the Jenkins
test report they show as skipped, and each regression shows as a failure.

Tests listed in `flaky/<TESTS_REF>.txt` or `flaky/common.txt` give different results between runs against the same
Snowstorm build. They are run and reported but can't fail the build or enter the baseline.

## Jenkins setup

Create a Pipeline job (for example `_FhirTxTests_`) using "Pipeline script from SCM", pointing
at this repository's `snowstorm-tx-tests` branch (kept apart from `main`, which mirrors upstream HL7) with script path `Jenkinsfile`. The agent needs Docker, git,
curl and python3. Java 25 and Maven run in the `amazoncorretto:25` and
`maven:3.9-amazoncorretto-25` images, and the Maven build shares the Jenkins user's `~/.m2`.
The nightly cron trigger takes effect after the job's first run.

When a build of Snowstorm `develop` fails, a Slack alert goes to the channel set for `snowstorm`
in the Code Estate spreadsheet. The job looks that up with snomed-jenkins'
`$SCRIPTS_PATH/PipelineGetConfig.sh`. Builds of other branches don't send alerts.

Each build archives `test-results/`. That includes `report.json`, `junit.xml`, `snowstorm.log`
and `baseline-passing.txt`, which lists the tests that passed in that build.

## Baselines

Different IG versions and different validator versions give different results, so each pair
has its own baseline: `baselines/<TESTS_REF>/validator-<version>.txt`, for example
`baselines/1.9.1/validator-6.9.9.txt`. The validator version is read from `report.json`, so
`VALIDATOR_VERSION=latest` picks the baseline for whichever release it downloaded. In
`TESTS_REF`, a `/` is replaced by `-`, and a blank `TESTS_REF` uses `head`.

The job scripts always come from the job branch. Only `tests/` and `tx-source/` are taken from
`TESTS_REF`, so to test another IG release or validator, run the job with those parameters.
You don't need a separate branch.

If a pair has no baseline file, the build runs in report-only mode, where no test can fail the
build. To add a baseline:

1. Run the job with the new `TESTS_REF` and/or `VALIDATOR_VERSION`.
2. Commit the archived `baseline-passing.txt` as
   `jenkins/baselines/<TESTS_REF>/validator-<version>.txt`.
3. Run the job a few more times, and list in `jenkins/flaky/<TESTS_REF>.txt` any test whose
   result changes between runs.

When Snowstorm fixes a test, the build log lists it under "Newly passing". To record it,
replace that pair's baseline with the `baseline-passing.txt` archived by that build and commit
the change.

## Running locally

```
export SNOWSTORM_SRC=../snowstorm TESTS_ROOT=$PWD/tests-src
jenkins/checkout-tests.sh 1.9.1      # blank ref uses this checkout's own tests
jenkins/snowstorm.sh build
jenkins/snowstorm.sh up
jenkins/snowstorm.sh load
jenkins/run-tx-tests.sh              # TX_FILTER=snomed-expand-count-all for a single test
python3 jenkins/check-regressions.py --tests-ref 1.9.1
jenkins/snowstorm.sh down
```

`run-tx-tests.sh` replaces the contents of `test-results/`. The stack needs about 4 GB of
Docker memory.
