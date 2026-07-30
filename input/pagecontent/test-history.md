This page details the changes made to the terminology tests over time, based on the GitHub releases. Note that the GitHub repository that contains these tests also contains many other test cases for other kinds of functionality; this history only lists releases that include changes to the terminology tests.

### 1.9.3

* Fix the SNOMED CT test set URL: correct the edition/version identifier used across the SNOMED test cases to the terminology-ecosystem test edition (`http://snomed.info/xsct/31000003106/version/20250909`), updating the affected requests and expected responses (display names and version URIs) to match

### 1.9.2

This is preparatory for settling the SNOMED CT tests, and then it will be labelled as 2.0.0

* Extensive SNOMED CT ECL testing: reorganised and greatly expanded the ECL tests — operator grouping and precedence (grouped-or / grouped-and, ambiguous precedence), cardinality and role-group occurrence counting, complex refinements and exclusions, and wildcard expansions; require `valueset-unclosed` on filter-based ECL expansions; and tests for enumerating grammar-based code systems (including `count=0` counts)
* Add test cases for the new `$compare` operation (previously named `$related`)
* Translate improvements: reverse translation, and `originMap` (replacing `sourceMap`)
* More code system version-control tests: value sets including/excluding different versions of the same code system, version pinning across all SNOMED requests, and version-dependent translate tests
* Tests for complex exclusions, contained value sets, `child-of`, and regex filters — including a regex denial-of-service case and improved regex error messages
* Search `$expand`: flat result format (`response:flat`) and support for the `total` OUT parameter
* Warnings for status / retired / inactive codes, with fixes to the reported location
* Display-name consistency, additional language and secondary-display tests, and allow `designation.use.display` in responses
* Validate a `CodeableConcept` using the first matching code rather than the last
* Content refresh: LOINC 2.82, updated SNOMED test load-set and version URIs, and updated VSAC content
* Numerous renames, parameter-name and typo fixes for consistency, unique value set ids, and removal of stale parameters (non-standard `limit` replaced by `count`, bad `cache-id`)

### 1.9.0

* Add a set of tests for controlling the version of CodeSystems (`ValueSet.compose.include.version`, with wildcards, and the expansion parameters `system-version` etc.)
* Revisit the tests to ensure that they are correct
* Remove the deprecated `version` parameter that is no longer used or supported (after 1 year of grace)
* Various improvements to error messages and test descriptions

### 1.7.7-SNAPSHOT

* Define `hierarchyMeaning` for the simple CodeSystem

### 1.7.6

* Allow `expansion.id` & `expansion.offset` in many tests
* Rename `valueset-version` to `default-valueset-version`
* tx.fhir.org only: Add supplement test cases and LOINC tests for CLASSTYPE, answers-for, and answer-list

### 1.7.5

* Add test for validation of `displayLanguage`

### 1.7.4

* Add message id

### 1.7.3

* Use `systemVersion` instead of `version`

### 1.7.2

* Add message-id extension to tests

### 1.7.1

* Remove language weights except where it matters
* Add `x-caused-by-unknown-system` when a supplement is not found
* Remove R4 variants

### 1.7.0

* Move master tests to tx-ecosystem-ig instead of general test cases

### 1.6.6

* Fix references to wrong value set in supplement tests

### 1.6.2

* Add specific tests for the interaction between `ValueSet.compose.inactive` and the `activeOnly` parameter
* Add tests for correctly populated CapabilityStatement and TerminologyCapabilities resources

### 1.6.0

There is no specific history for the terminology test cases prior to version 1.6.0. The only history notes available are mixed in with all the other kinds of tests in the GitHub release notes.
