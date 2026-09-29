// Nightly FHIR tx-ecosystem regression tests against a throwaway Snowstorm (MAINT-3099).
// The agent needs Docker, git, curl and python3; Java and Maven run in containers.
pipeline {
    agent any

    triggers {
        cron('H 2 * * 1-5')
    }

    parameters {
        string(name: 'SNOWSTORM_BRANCH', defaultValue: 'develop', description: 'Branch of IHTSDO/snowstorm to build and test')
        string(name: 'TESTS_REF', defaultValue: '1.9.1', description: 'Required. Tag, branch or commit of this repository to take tests/ and tx-source/ from. Regressions are judged against jenkins/baselines/<ref>/validator-<version>.txt; a pair without one is reported on only and marked unstable')
        string(name: 'VALIDATOR_VERSION', defaultValue: '6.9.9', description: 'hapifhir/org.hl7.fhir.core release tag for validator_cli.jar, or "latest"')
        string(name: 'ELASTICSEARCH_VERSION', defaultValue: '', description: "Elasticsearch image tag; blank uses the one in Snowstorm's docker-compose.yml")
        string(name: 'TX_FILTER', defaultValue: '', description: 'Optional txTests -filter, e.g. snomed-expand-count-all')
    }

    options {
        ansiColor('xterm')
        buildDiscarder(logRotator(numToKeepStr: '30'))
        disableConcurrentBuilds()
        timeout(time: 2, unit: 'HOURS')
    }

    environment {
        TX_TESTS_PREFIX = "txtests-${env.BUILD_TAG}"
        SNOWSTORM_SRC = "${env.WORKSPACE}/snowstorm-src"
        TESTS_ROOT = "${env.WORKSPACE}/tests-src"
    }

    stages {
        stage('Checkout Snowstorm') {
            steps {
                script {
                    if (!params.TESTS_REF?.trim()) {
                        error('TESTS_REF is required: the job branch does not follow main, so its own tests are out of date')
                    }
                    currentBuild.description = "Snowstorm ${params.SNOWSTORM_BRANCH}, tests ${params.TESTS_REF}, validator ${params.VALIDATOR_VERSION}"
                }
                dir('snowstorm-src') {
                    git url: 'https://github.com/IHTSDO/snowstorm.git', branch: params.SNOWSTORM_BRANCH, changelog: false, poll: false
                }
            }
        }
        stage('Checkout tests') { steps { sh 'jenkins/checkout-tests.sh' } }
        stage('Build Snowstorm') { steps { sh 'jenkins/snowstorm.sh build' } }
        stage('Start Snowstorm') { steps { sh 'jenkins/snowstorm.sh up' } }
        stage('Load SNOMED subset') { steps { sh 'jenkins/snowstorm.sh load' } }
        stage('Run tx tests') { steps { sh 'jenkins/run-tx-tests.sh' } }
        stage('Check regressions') {
            steps {
                script {
                    int status = sh(returnStatus: true,
                            script: 'python3 jenkins/check-regressions.py --tests-ref "$TESTS_REF" --write-baseline test-results/baseline-passing.txt')
                    if (status == 2) {
                        unstable('No baseline for this TESTS_REF and validator, so regressions were not checked')
                    } else if (status != 0) {
                        error(status == 1 ? 'Regressions found' : "check-regressions.py exited with status ${status}")
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'jenkins/snowstorm.sh down'
            junit testResults: 'test-results/junit.xml', allowEmptyResults: true, skipMarkingBuildUnstable: true
            archiveArtifacts artifacts: 'test-results/**', allowEmptyArchive: true
        }
        failure { script { notifySlack('failed', 'danger') } }
        unstable { script { notifySlack('were not checked against a baseline', 'warning') } }
    }
}

void notifySlack(String outcome, String color) {
    if (params.SNOWSTORM_BRANCH != 'develop') {
        return
    }
    // Borrow the snowstorm row of the Code Estate spreadsheet, as this job has none of its own.
    String channel = sh(returnStdout: true,
            script: 'JOB_NAME=jobs/snowstorm "$SCRIPTS_PATH/PipelineGetConfig.sh" failure || true').trim()
    if (channel && channel != '#') {
        slackSend channel: channel, color: color,
                message: "FHIR tx tests ${outcome} for Snowstorm ${params.SNOWSTORM_BRANCH} '${env.JOB_NAME}' Build${env.BUILD_DISPLAY_NAME} (<${env.BUILD_URL}|Open>)"
    } else {
        echo 'No Slack channel found for snowstorm in the Code Estate spreadsheet'
    }
}
