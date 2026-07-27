#!/usr/bin/env python3
"""Generate Swarm's deterministic offline GeoNames index."""

import argparse
import csv
from collections import defaultdict


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--all-countries", required=True)
    parser.add_argument("--alternate-names", required=True)
    parser.add_argument("--country-info", required=True)
    parser.add_argument("--admin1-codes", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--version", required=True)
    return parser.parse_args()


def clean(value):
    return value.replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def alternate_names(path):
    names = defaultdict(lambda: {"ru": [], "local": []})
    with open(path, encoding="utf-8", newline="") as source:
        for row in csv.reader(source, delimiter="\t"):
            if len(row) < 4 or row[2] not in {"ru", ""}:
                continue
            name = clean(row[3])
            bucket = "ru" if row[2] == "ru" else "local"
            if name and name not in names[row[1]][bucket]:
                names[row[1]][bucket].append(name)
    return names


def display_name(geoname_id, fallback, alternates):
    russian = alternates.get(geoname_id, {}).get("ru", [])
    return russian[0] if russian else clean(fallback)


def country_names(path, alternates):
    result = {}
    with open(path, encoding="utf-8") as source:
        for line in source:
            if line.startswith("#"):
                continue
            row = line.rstrip("\n").split("\t")
            if len(row) >= 17:
                result[row[0]] = display_name(row[16], row[4], alternates)
    return result


def admin1_names(path, alternates):
    result = {}
    with open(path, encoding="utf-8", newline="") as source:
        for row in csv.reader(source, delimiter="\t"):
            if len(row) >= 4:
                result[row[0]] = display_name(row[3], row[1], alternates)
    return result


def main():
    args = arguments()
    alternates = alternate_names(args.alternate_names)
    countries = country_names(args.country_info, alternates)
    regions = admin1_names(args.admin1_codes, alternates)

    rows = []
    with open(args.all_countries, encoding="utf-8", newline="") as source:
        for row in csv.reader(source, delimiter="\t"):
            if len(row) < 19 or row[6] not in {"P", "A"}:
                continue
            geoname_id = row[0]
            name = display_name(geoname_id, row[1], alternates)
            local_aliases = [clean(row[1]), clean(row[2])]
            local_aliases += alternates.get(geoname_id, {}).get("ru", [])
            local_aliases += alternates.get(geoname_id, {}).get("local", [])
            local_aliases = list(dict.fromkeys(value for value in local_aliases if value and value != name))
            rows.append((
                int(geoname_id), name, "|".join(local_aliases),
                regions.get(f"{row[8]}.{row[10]}", clean(row[10])),
                countries.get(row[8], clean(row[8])), row[4], row[5], args.version,
            ))

    rows.sort(key=lambda value: value[0])
    with open(args.output, "w", encoding="utf-8", newline="") as destination:
        writer = csv.writer(destination, delimiter="\t", lineterminator="\n")
        writer.writerow(("geoname_id", "display_name", "aliases", "region", "country", "latitude", "longitude", "dataset_version"))
        writer.writerows(rows)


if __name__ == "__main__":
    main()
