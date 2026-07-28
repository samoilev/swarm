# Third-party notices

Swarm bundles no third-party Swift packages. It does bundle third-party **data**,
listed below with its source and license. The MIT license in [LICENSE](LICENSE)
covers Swarm's own source code only — it does not relicense the datasets.

## Bundled datasets

| File | Source | License | Notes |
| --- | --- | --- | --- |
| `Swarm/Core/Resources/place_index_v2.tsv` | [GeoNames](https://www.geonames.org/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Seed snapshot, version `2026-07-15-seed`. Generated from an official GeoNames dump by `Scripts/generate_place_index.py`. Columns and regeneration command are documented in [`PLACE_DATA.md`](Swarm/Core/Resources/PLACE_DATA.md). |
| `Swarm/Core/Resources/places.tsv` | [GeoNames](https://www.geonames.org/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Legacy snapshot, ~22 MB. Derived and modified: reduced to Russian display name, administrative region and country; original GeoNames IDs were not retained (the app assigns deterministic `local-` identifiers instead). **The upstream dump date was not recorded.** |
| `Swarm/Core/Resources/geonames_ussr.tsv` | [GeoNames](https://www.geonames.org/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Legacy coordinate/alias snapshot, ~8 MB. Derived and modified: reduced to alias, latitude and longitude, filtered to the former USSR region. **The upstream dump date was not recorded.** |
| `Swarm/Core/Resources/ne_110m_land.geojson` | [Natural Earth](https://www.naturalearthdata.com/) 1:110m, via the [`nvkelso/natural-earth-vector`](https://github.com/nvkelso/natural-earth-vector) mirror | Public domain | Used only by the offline `Canvas` map renderer. See [`MAP_DATA.md`](Swarm/Core/Resources/MAP_DATA.md). |
| `Swarm/Core/Resources/ne_110m_admin_0_boundary_lines_land.geojson` | [Natural Earth](https://www.naturalearthdata.com/downloads/110m-cultural-vectors/) 1:110m, same mirror | Public domain | As above. |

### GeoNames attribution

> Contains GeoNames data, available from https://www.geonames.org/.

GeoNames data is licensed under [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
The bundled snapshots are **modified** versions of that data, as described in the table above.

### Natural Earth

Natural Earth vector data is in the public domain and carries no attribution requirement.
It is credited here as a courtesy, per the
[Natural Earth terms of use](https://www.naturalearthdata.com/about/terms-of-use/).

## Trademarks

Ancestry, Gramps and MyHeritage are named in this project's documentation and test
fixtures solely to describe GEDCOM interoperability testing. Swarm is not affiliated
with, endorsed by, or sponsored by any of them. All trademarks are the property of
their respective owners.

## The Swarm name and icon

The MIT license covers the source code. It does **not** grant rights to the "Swarm"
name or to the application icon and other brand artwork. If you fork or redistribute a
modified build, please give it a different name and icon so users can tell the projects
apart.
