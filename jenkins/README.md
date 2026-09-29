# Snowstorm tx-ecosystem regression job

The `Jenkinsfile` at the repository root does the following:

1. Builds Snowstorm and runs it against a throwaway Elasticsearch in Docker.
2. Takes `tests/` and `tx-source/` from the IG release named by `TESTS_REF` (default `1.9.1`).
3. Loads the `tx-source/snomed` subset as the SNOMED CT version those tests expect. The load
   step reads that version from the tests: for `1.9.1` it is
   `http://snomed.info/xsct/900000000000207008/version/20250814`.
4. Runs the tests (modes `general`, `snomed` and `flat`; `flat` because Snowstorm returns non-hierarchical expansions) with the HL7 validator's `txTests` command.
5. Fails the build if a test listed in the baseline for that `TESTS_REF` and validator,
   `baselines/<TESTS_REF>/validator-<version>.txt`, no longer passes or was not run. A test that
   was not run usually means txTests stopped early. When `TX_FILTER` is set, baseline tests
   the filter leaves out are not counted.

Many tests do not pass on Snowstorm yet, so they are not treated as failures. In the Jenkins
test report they show as skipped, and each regression shows as a failure.

Tests listed in `flaky/<TESTS_REF>.txt` or `flaky/common.txt` give different results between runs against the same
Snowstorm build. They are run and reported but can't fail the build or enter the baseline.

## Jenkins setup

### Agent

The build agent needs:

- Docker, git, curl and python3. The Jenkins user must be able to run `docker` without sudo,
  for example by being in the `docker` group.
- About 4 GB of free memory for Docker.
- Network access to GitHub, Docker Hub and `docker.elastic.co`.

Java 25 and Maven run in the `amazoncorretto:25` and `maven:3.9-amazoncorretto-25` images, and
the Maven build shares the Jenkins user's `~/.m2`. The Jenkinsfile uses `agent any`. If some
agents don't have Docker, pin the job to one that does, with "Restrict where this project can
be run" or an `agent { label '...' }`.

Plugins: Declarative Pipeline, Git, JUnit, AnsiColor and Slack Notification.

### Creating the job

1. Go to **New Item**, enter a name (for example `_FhirTxTests_`), choose **Pipeline**, then OK.
2. Under **Pipeline**, set **Definition** to *Pipeline script from SCM* and fill in:
   - **SCM**: Git
   - **Repository URL**: `https://github.com/IHTSDO/fhir-tx-ecosystem-ig.git` (public, so no
     credentials are needed)
   - **Branch Specifier**: `*/snowstorm-tx-tests`. This branch is kept apart from `main`,
     which mirrors upstream HL7.
   - **Script Path**: `Jenkinsfile`
3. Leave the remote name as the default, `origin`, because `checkout-tests.sh` fetches the
   tests from it. Don't disable tag fetching.
4. Save. You don't need to add parameters, a build trigger or build retention settings; they're
   all in the Jenkinsfile.

If SNOMED jobs are created by snomed-jenkins rather than by hand, register this job that way
instead, with the same settings.

### First run

Click **Build Now**. The first build registers the parameters and the nightly schedule
(around 02:00, Monday to Friday) and runs with the defaults: Snowstorm `develop`, tests `1.9.1`
and validator `6.9.9`. After that, use **Build with Parameters** to test other IG versions,
validators or Snowstorm branches. A build times out after 2 hours.

### Build results

- **Green:** no regressions against the baseline.
- **Yellow (unstable):** there's no baseline for that `TESTS_REF` and validator. The log names
  the file it looked for.
- **Red:** there are regressions or baseline tests that didn't run. They're listed in the log
  and in the **Test Result** page.

Each build archives `test-results/`. That includes `report.json`, `junit.xml`, `snowstorm.log`
and `baseline-passing.txt`, which lists the tests that passed in that build.

When a build of Snowstorm `develop` fails or is unstable, a Slack alert goes to the channel set
for `snowstorm` in the Code Estate spreadsheet. The first green build after that sends a
"passing again" message. The job looks that up with snomed-jenkins'
`$SCRIPTS_PATH/PipelineGetConfig.sh`, so `SCRIPTS_PATH` must be set on the agent. Without it,
the build still works, but no alert goes out and the log says "No Slack channel found".
Builds of other branches don't send alerts.

## Baselines

Different IG versions and different validator versions give different results, so each pair
has its own baseline: `baselines/<TESTS_REF>/validator-<version>.txt`, for example
`baselines/1.9.1/validator-6.9.9.txt`. The validator version is read from `report.json`, so
`VALIDATOR_VERSION=latest` picks the baseline for whichever release it downloaded. In
`TESTS_REF`, a `/` is replaced by `-`.

The job scripts always come from the job branch. Only `tests/` and `tx-source/` are taken from
`TESTS_REF`, so to test another IG release or validator, run the job with those parameters.
You don't need a separate branch. `TESTS_REF` is required, because the job branch doesn't
follow `main`, so its own `tests/` are out of date.

HL7 doesn't tag IG releases upstream, and `checkout-tests.sh` fetches only from `origin`
(IHTSDO/fhir-tx-ecosystem-ig). Tags such as `1.9.1` are created in this fork. To test a newer
version:

1. Sync the fork's `main` with `upstream/main`.
2. Tag the commit you want and push the tag, for example
   `git tag 1.9.2 <commit> && git push origin 1.9.2`.

A commit SHA also works as `TESTS_REF`, but its baselines are then filed under that SHA.

If a pair has no baseline file, the build runs in report-only mode and is marked unstable, so a
new validator or IG version can't quietly stop the regression checks. To add a baseline:

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
