# Local place data

FamilyTreeStudio searches a bundled, versioned place snapshot. No query is sent to a
network service. `places.tsv` contains Russian display names, administrative regions
and countries; `geonames_ussr.tsv` contains the coordinate/alias snapshot used by the
current internal build. `place_index_v2.tsv` seeds original GeoNames IDs for the most
common locations and is loaded first. The two legacy snapshots remain one searchable
fallback index and use a deterministic `local-` identifier when their original ID is
unavailable.

For the production v2 dataset, generate `place_index_v2.tsv` from an official
GeoNames dump with:

```sh
python3 Scripts/generate_place_index.py \
  --all-countries allCountries.txt \
  --alternate-names alternateNamesV2.txt \
  --country-info countryInfo.txt \
  --admin1-codes admin1CodesASCII.txt \
  --output FamilyTreeStudio/Core/Resources/place_index_v2.tsv \
  --version 2026-07-15
```

The generated columns are:

```text
geoname_id<TAB>display_name<TAB>aliases<TAB>region<TAB>country<TAB>latitude<TAB>longitude<TAB>dataset_version
```

`aliases` is a pipe-separated, deduplicated list containing Russian, canonical and
local names. Russian names are used as display names where available; country and
first-order region codes are resolved through the companion GeoNames files. The
generator keeps populated places and administrative features, sorts by the numeric
GeoNames ID, and emits UTF-8 with LF line endings. Dataset updates must not
rewrite places already stored in a tree: a `PlaceReference` retains its selected ID,
display-name snapshot and coordinates.

GeoNames data is licensed under Creative Commons Attribution 4.0. Attribution:
“Contains GeoNames data, available from https://www.geonames.org/.” Record the dump
date in the `--version` column and in internal release notes.

The bundled seed snapshot version is `2026-07-15-seed`. It is deliberately small;
internal production packaging should regenerate the full `place_index_v2.tsv` using
the command above before declaring complete global GeoNames-ID coverage.
