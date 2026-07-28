# Local place data

Swarm searches one bundled, versioned bilingual GeoNames snapshot. Place search,
free-text coordinate resolution, selected-place presentation, and offline map labels
all read `place_index_v2.tsv`; no place query is sent to a network service.

The bundled snapshot is pinned to the official GeoNames daily exports downloaded on
**2026-07-28** and carries dataset version `geonames-2026-07-28`. It contains 476,958
populated places:

- every populated-place record in Armenia, Azerbaijan, Belarus, Estonia, Georgia,
  Kazakhstan, Kyrgyzstan, Latvia, Lithuania, Moldova, Russia, Tajikistan,
  Turkmenistan, Ukraine, and Uzbekistan;
- populated places with population at least 500 in the GeoNames `EU` and `NA`
  continents;
- all populated-place national and administrative seats (`PPLC`, `PPLA*`) in those
  two continents. GeoNames `NA` includes Central America and the Caribbean.

The exact columns are:

```text
geoname_id, feature_code, population, name_ru, name_en, name_local, aliases,
region_ru, region_en, country_ru, country_en, country_code, continent_code,
latitude, longitude, dataset_version
```

The file is UTF-8, tab-delimited, and uses LF line endings. Aliases are pipe-delimited.
Russian and English display names prefer non-historic preferred alternatives;
canonical/local, ASCII, historic, colloquial, and useful transliterated variants stay
searchable. Search folds case, width, diacritics, and Russian `ё/е`.

## Rebuilding the snapshot

Download these files from the [official GeoNames daily export](https://download.geonames.org/export/dump/):

- `allCountries.zip`
- `alternateNamesV2.zip`
- `countryInfo.txt`
- `admin1CodesASCII.txt`

After extracting the two archives:

```sh
python3 Scripts/generate_place_index.py \
  --all-countries allCountries.txt \
  --alternate-names alternateNamesV2.txt \
  --country-info countryInfo.txt \
  --admin1-codes admin1CodesASCII.txt \
  --output Swarm/Core/Resources/place_index_v2.tsv \
  --version geonames-2026-07-28
```

The generator filters before retaining alternate names, sorts by numeric GeoNames ID,
and emits byte-identical output for identical inputs. Update the version date here,
in `THIRD_PARTY_NOTICES.md`, and in the changelog whenever the snapshot changes.

`PlaceReference` remains the archival snapshot: saved display text, GeoNames ID, and
coordinates are never rewritten on a language switch or dataset update. Views and PDFs
may resolve a current localized label by ID; custom/imported text without a known ID is
family-record data and is never translated. A free-text coordinate is accepted only
for an exact localized full address or a globally unique bare name/alias.

GeoNames data is licensed under Creative Commons Attribution 4.0:
“Contains GeoNames data, available from https://www.geonames.org/.”
