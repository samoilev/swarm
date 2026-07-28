#!/usr/bin/env python3
"""Generate Swarm's deterministic bilingual offline GeoNames index.

Coverage:
* every populated-place row in the 15 current former-USSR countries;
* populated places with population >= 500 in GeoNames continent EU or NA;
* all populated-place national/admin seats (PPLC/PPLA*) in EU or NA.

The script intentionally performs two streaming passes. It first selects the target
GeoNames IDs, then retains alternate names only for those places and the country/admin
records needed to localise their addresses. This keeps a global daily dump practical.
"""

import argparse
import csv
from collections import defaultdict
from dataclasses import dataclass


FORMER_USSR = {
    "AM", "AZ", "BY", "EE", "GE", "KZ", "KG", "LV", "LT", "MD",
    "RU", "TJ", "TM", "UA", "UZ",
}
TARGET_CONTINENTS = {"EU", "NA"}
ADMIN_FEATURE_PREFIX = "PPLA"
EXCLUDED_ALIAS_LANGUAGES = {"link", "wkdt", "post", "iata", "icao", "faac"}
MAX_ALIASES = 64
MANUAL_ALIASES = {
    "625144": ["Менск"],
    "498817": ["Ленинград", "Петроград"],
    "1486209": ["Свердловск"],
    "520555": ["Горький"],
    "499099": ["Куйбышев"],
    "472757": ["Сталинград"],
    "480060": ["Калинин"],
    "1526273": ["Нур-Султан"],
}
HEADER = (
    "geoname_id", "feature_code", "population", "name_ru", "name_en",
    "name_local", "aliases", "region_ru", "region_en", "country_ru",
    "country_en", "country_code", "continent_code", "latitude", "longitude",
    "dataset_version",
)


@dataclass(frozen=True)
class Country:
    code: str
    name: str
    continent: str
    geoname_id: str


@dataclass(frozen=True)
class Admin:
    code: str
    name: str
    ascii_name: str
    geoname_id: str


@dataclass(frozen=True)
class Place:
    geoname_id: str
    name: str
    ascii_name: str
    latitude: str
    longitude: str
    feature_code: str
    country_code: str
    admin1_code: str
    population: int


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
    return (
        value.replace("\t", " ")
        .replace("\r", " ")
        .replace("\n", " ")
        .replace("|", "¦")
        .strip()
    )


def read_countries(path):
    result = {}
    with open(path, encoding="utf-8") as source:
        for line in source:
            if line.startswith("#"):
                continue
            row = line.rstrip("\n").split("\t")
            if len(row) >= 17:
                result[row[0]] = Country(
                    code=row[0],
                    name=clean(row[4]),
                    continent=clean(row[8]),
                    geoname_id=clean(row[16]),
                )
    return result


def read_admins(path):
    result = {}
    with open(path, encoding="utf-8", newline="") as source:
        for row in csv.reader(source, delimiter="\t"):
            if len(row) >= 4:
                result[row[0]] = Admin(
                    code=row[0],
                    name=clean(row[1]),
                    ascii_name=clean(row[2]),
                    geoname_id=clean(row[3]),
                )
    return result


def selected_places(path, countries):
    result = []
    with open(path, encoding="utf-8", newline="") as source:
        for row in csv.reader(source, delimiter="\t"):
            if len(row) < 19 or row[6] != "P":
                continue
            country_code = row[8]
            country = countries.get(country_code)
            if not country:
                continue
            try:
                population = int(row[14] or 0)
            except ValueError:
                population = 0
            feature_code = row[7]
            in_former_ussr = country_code in FORMER_USSR
            in_western_scope = country.continent in TARGET_CONTINENTS
            is_admin_seat = feature_code == "PPLC" or feature_code.startswith(ADMIN_FEATURE_PREFIX)
            if not in_former_ussr and not (
                in_western_scope and (population >= 500 or is_admin_seat)
            ):
                continue
            result.append(Place(
                geoname_id=row[0],
                name=clean(row[1]),
                ascii_name=clean(row[2]),
                latitude=clean(row[4]),
                longitude=clean(row[5]),
                feature_code=feature_code,
                country_code=country_code,
                admin1_code=row[10],
                population=population,
            ))
    return result


def alternate_score(row):
    preferred = row[4] == "1" if len(row) > 4 else False
    short = row[5] == "1" if len(row) > 5 else False
    colloquial = row[6] == "1" if len(row) > 6 else False
    historic = row[7] == "1" if len(row) > 7 else False
    return (
        0 if historic else 100,
        30 if preferred else 0,
        5 if short else 0,
        0 if colloquial else 2,
    )


def alternate_names(path, target_ids):
    # Each item is (score tuple, name, language, historic, colloquial).
    names = defaultdict(list)
    with open(path, encoding="utf-8", newline="") as source:
        for row in csv.reader(source, delimiter="\t"):
            if len(row) < 4 or row[1] not in target_ids:
                continue
            language = row[2]
            name = clean(row[3])
            if not name or language in EXCLUDED_ALIAS_LANGUAGES:
                continue
            historic = len(row) > 7 and row[7] == "1"
            colloquial = len(row) > 6 and row[6] == "1"
            preferred = len(row) > 4 and row[4] == "1"
            # Keep normal ru/en/unlabelled names plus preferred, historic and
            # colloquial variants from other languages as archival search aliases.
            if language not in {"ru", "en", ""} and not (
                preferred or historic or colloquial
            ):
                continue
            names[row[1]].append((
                alternate_score(row), name, language, historic, colloquial,
            ))
    return names


def preferred_name(geoname_id, language, fallback, alternates):
    candidates = [
        value for value in alternates.get(geoname_id, [])
        if value[2] == language and not value[3]
    ]
    if not candidates:
        return clean(fallback)
    candidates.sort(key=lambda value: (value[0], value[1]), reverse=True)
    return candidates[0][1]


def aliases_for(place, name_ru, name_en, alternates):
    candidates = [
        (1000, place.name),
        (990, place.ascii_name),
    ]
    candidates.extend(
        (1200, value) for value in MANUAL_ALIASES.get(place.geoname_id, [])
    )
    for score, name, language, historic, colloquial in alternates.get(
        place.geoname_id, []
    ):
        priority = sum(score)
        if language == "ru":
            priority += 500
        elif language == "en":
            priority += 450
        elif language == "":
            priority += 300
        if historic:
            priority += 200
        if colloquial:
            priority += 100
        candidates.append((priority, name))

    result = []
    seen = {name_ru.casefold(), name_en.casefold()}
    for _, value in sorted(candidates, key=lambda item: (-item[0], item[1].casefold())):
        cleaned = clean(value)
        key = cleaned.casefold()
        if cleaned and key not in seen:
            seen.add(key)
            result.append(cleaned)
        if len(result) >= MAX_ALIASES:
            break
    return result


def main():
    args = arguments()
    countries = read_countries(args.country_info)
    admins = read_admins(args.admin1_codes)
    places = selected_places(args.all_countries, countries)

    target_ids = {place.geoname_id for place in places}
    target_ids.update(
        countries[place.country_code].geoname_id
        for place in places
        if place.country_code in countries
    )
    target_ids.update(
        admins[f"{place.country_code}.{place.admin1_code}"].geoname_id
        for place in places
        if f"{place.country_code}.{place.admin1_code}" in admins
    )
    alternates = alternate_names(args.alternate_names, target_ids)

    rows = []
    for place in places:
        country = countries[place.country_code]
        admin = admins.get(f"{place.country_code}.{place.admin1_code}")
        name_ru = preferred_name(
            place.geoname_id, "ru", place.name, alternates
        )
        name_en = preferred_name(
            place.geoname_id, "en", place.ascii_name or place.name, alternates
        )
        country_ru = preferred_name(
            country.geoname_id, "ru", country.name, alternates
        )
        country_en = preferred_name(
            country.geoname_id, "en", country.name, alternates
        )
        region_ru = ""
        region_en = ""
        if admin:
            region_ru = preferred_name(
                admin.geoname_id, "ru", admin.name, alternates
            )
            region_en = preferred_name(
                admin.geoname_id, "en", admin.ascii_name or admin.name, alternates
            )
        rows.append((
            int(place.geoname_id),
            place.feature_code,
            place.population,
            name_ru,
            name_en,
            place.name,
            "|".join(aliases_for(place, name_ru, name_en, alternates)),
            region_ru,
            region_en,
            country_ru,
            country_en,
            place.country_code,
            country.continent,
            place.latitude,
            place.longitude,
            clean(args.version),
        ))

    # Stable ID order makes diffs useful and reruns byte-identical.
    rows.sort(key=lambda value: value[0])
    with open(args.output, "w", encoding="utf-8", newline="") as destination:
        writer = csv.writer(destination, delimiter="\t", lineterminator="\n")
        writer.writerow(HEADER)
        writer.writerows(rows)


if __name__ == "__main__":
    main()
