#!/usr/bin/env python3
"""Compare a txTests report.json with the baseline of tests known to pass on Snowstorm.

Exits 1 when a baseline test no longer passes, or was not run at all unless --tx-filter is set.
Newly passing tests are reported so the baseline can be ratcheted up with --write-baseline.
A JUnit file is written for Jenkins: regressions are failures, tests not yet in the baseline
are skipped, the rest pass.
Tests listed in the flaky files are run and reported but never fail the build or enter the baseline.
Baselines are kept per IG version and validator version, in
jenkins/baselines/<ref>/validator-<version>.txt, and flaky lists per IG version, in
jenkins/flaky/<ref>.txt. A run with no baseline for its pair is reported on only, and exits 2
so that Jenkins can mark it unstable.
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from xml.etree import ElementTree as ET


def load_results(report_path):
    report = json.loads(Path(report_path).read_text())
    results = {}
    for test in report.get("test", []):
        operation = test["action"][0]["operation"]
        if operation["result"] != "skip":
            results[test["name"]] = (operation["result"], operation.get("message", ""))
    return report, results


def load_names(*paths):
    names = set()
    for path in paths:
        if Path(path).exists():
            lines = Path(path).read_text().splitlines()
            names |= {line.strip() for line in lines if line.strip() and not line.startswith("#")}
    return names


def validator_version(report):
    match = re.search(r"v(\S+)$", report.get("tester", ""))
    return match.group(1) if match else "unknown"


def ref_key(ref):
    return ref.strip().replace("/", "-") or "head"


def write_junit(path, results, flaky, regressions, not_run):
    suites = defaultdict(list)
    for name, outcome in results.items():
        suite, _, test = name.partition("/")
        suites[suite].append((test, name, outcome))
    for name in not_run:
        suite, _, test = name.partition("/")
        suites[suite].append((test, name, ("not run", "In the baseline but not in report.json")))

    root = ET.Element("testsuites", name="tx-ecosystem")
    for suite_name, tests in suites.items():
        suite = ET.SubElement(root, "testsuite", name=suite_name, tests=str(len(tests)))
        for test, name, (result, message) in tests:
            case = ET.SubElement(suite, "testcase", classname=f"tx-ecosystem.{suite_name}", name=test)
            if name in regressions:
                ET.SubElement(case, "failure", message="Regression: passed in baseline").text = message
            elif name in not_run:
                ET.SubElement(case, "failure", message="Regression: in the baseline but not run").text = message
            elif result != "pass":
                reason = "Flaky, ignored" if name in flaky else "Known failure (not in baseline)"
                ET.SubElement(case, "skipped", message=reason).text = message
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--report", default="test-results/report.json")
    parser.add_argument("--tests-ref", default=os.environ.get("TESTS_REF", ""),
                        help="IG version the tests came from; picks the baseline and flaky list (default $TESTS_REF)")
    parser.add_argument("--baseline", help="Default: jenkins/baselines/<ref>/validator-<version in the report>.txt")
    parser.add_argument("--flaky", action="append",
                        help="May be repeated. Default: jenkins/flaky/<ref>.txt and jenkins/flaky/common.txt")
    parser.add_argument("--tx-filter", default=os.environ.get("TX_FILTER", ""),
                        help="txTests -filter the run used; baseline tests it left out are not counted (default $TX_FILTER)")
    parser.add_argument("--junit", default="test-results/junit.xml")
    parser.add_argument("--write-baseline", metavar="PATH",
                        help="Also write the tests passing in this run to PATH, in baseline format")
    args = parser.parse_args()
    key = ref_key(args.tests_ref)
    flaky_paths = args.flaky or [f"jenkins/flaky/{key}.txt", "jenkins/flaky/common.txt"]

    report, results = load_results(args.report)
    validator = validator_version(report)
    baseline_path = args.baseline or f"jenkins/baselines/{key}/validator-{validator}.txt"
    report_only = not Path(baseline_path).exists()
    flaky = load_names(*flaky_paths)
    baseline = load_names(baseline_path) - flaky
    passing = {name for name, (result, _) in results.items() if result == "pass"}

    regressions = sorted(name for name in baseline if name in results and name not in passing)
    newly_passing = sorted(passing - baseline - flaky)
    not_run = [] if args.tx_filter else sorted(baseline - results.keys())
    flaky_failing = sorted(name for name in flaky if name in results and name not in passing)

    write_junit(args.junit, results, flaky, set(regressions), set(not_run))

    server = next((p.get("display") for p in report.get("participant", [])), "unknown server")
    print(f"{report.get('tester', 'txTests')} against {server}")
    if report_only:
        print(f"No baseline for {key} with validator {validator} ({baseline_path}); reporting only")
    print(f"{len(passing)}/{len(results)} passed; baseline has {len(baseline)} tests")

    for title, names in (("Newly passing (add to the baseline)", newly_passing),
                         ("Flaky tests that failed this time (ignored)", flaky_failing)):
        if names:
            print(f"\n{title}: {len(names)}")
            for name in names:
                print(f"  {name}")

    if regressions:
        print(f"\nREGRESSIONS: {len(regressions)}")
        for name in regressions:
            message = results[name][1].replace("\n", " ")
            print(f"  {name}: {message}")

    if not_run:
        print(f"\nREGRESSIONS - in the baseline but not run (txTests stopped early, or renamed or removed?): {len(not_run)}")
        for name in not_run:
            print(f"  {name}")

    if args.write_baseline:
        Path(args.write_baseline).write_text(
            "# Tests that pass on Snowstorm; a failure of any of these fails the Jenkins build.\n"
            f"# Regenerate with: jenkins/check-regressions.py --tests-ref {args.tests_ref or key} --write-baseline {baseline_path}\n"
            + "".join(f"{name}\n" for name in sorted(passing - flaky)))
        print(f"\nWrote {len(passing - flaky)} passing tests to {args.write_baseline}")

    if regressions or not_run:
        return 1
    return 2 if report_only else 0


if __name__ == "__main__":
    sys.exit(main())
