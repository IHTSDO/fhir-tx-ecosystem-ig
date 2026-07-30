# Introduction
This folder contains testing material for large external code systems;
these are the sources for the test cases on LOINC, SNOMED CT etc.

What follows is notes about how to prepare the subsets

## SNOMED CT
The data under the `snomed` folder is a small test subontology with effective time 20250909, extracted from the International August 2025 release. 

The snapshot must be imported with a specific URI `http://snomed.info/xsct/31000003106/version/20250909`.
- `xsct` means unpublished release
- `31000003106` is the Test subontology module.

The `snomed-expand-count-all` test can be used to verify the loaded concept count.

### Snowstorm Tip
Import with the `internalRelease` flag to ensure an unpublished URI is generated.

### SNOMED Subset Generation Process
_Generating the subontology is not necessary because the output files are already available in the `snomed` folder._

If you want to recreate the subset, first create the OWL Ontology file using the [SNOMED OWL Toolkit](https://github.com/IHTSDO/snomed-owl-toolkit).
```
java -jar --add-opens java.base/java.lang=ALL-UNNAMED snomed-owl-toolkit-executable.jar -rf2-to-owl \ 
 -rf2-snapshot-archives SnomedCT_InternationalRF2_PRODUCTION_20250801T120000Z.zip -version 20250801
```
Then take `snomed-subset.txt` from this repository and run the [SNOMED Subontology Extraction](https://github.com/IHTSDO/snomed-subontology-extraction) tool to create the subontology with effective time 20250909:
```
java -jar --add-opens java.base/java.lang=ALL-UNNAMED snomed-subontology-extraction-executable.jar \
 -source-ontology ontology-20250801.owl -input-subset snomed-subset.txt -output-rf2 -rf2-snapshot-archive SnomedCT_InternationalRF2_PRODUCTION_20250801T120000Z.zip \
 -include-inactive -effective-time 20250909
```

## LOINC CT

The subset is prepared by the code at https://github.com/HealthIntersections/nodeserver,
and running

```
npm install
tx-import loinc-subset
```

You then have to provide a reference to a downloaded LOINC source, 
and a list of LOINC codes to import, which is found in
loinc-subset.txt in this folder

## NDC

The test set is prepared by hand by taking subsets
from the first few lines of NDC

