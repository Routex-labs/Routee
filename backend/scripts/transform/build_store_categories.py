"""공식 층별안내 스냅샷에서 매장명 기준 카테고리 매핑을 만든다.

입력은 `resources/official_floor_guide.json`(원본 스냅샷)과
`resources/category_section_map.json`(섹션 -> 우리 분류 매핑표)이고, 산출물은
`resources/store_category_by_name.json`이다. 판단 근거는
`docs/backend/store-category-resurvey.md`.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path
from typing import TypedDict


class Report(TypedDict):
    """생성 결과 중 **사람이 눈으로 봐야 하는** 잔여 항목. 비어 있는 것이 정상이다."""

    unknownSections: list[str]
    unmatchedOfficial: list[str]
    orphanEntries: list[str]
    localOnlyMissing: list[str]
    aliasMissing: list[str]
    duplicateOfficialNames: list[str]
    appliedFromOfficial: int


API_ROOT = Path(__file__).resolve().parents[2]
RESOURCES = API_ROOT / "resources"
STUDIO_DIR = RESOURCES / "studio" / "thehyundai-seoul-dabeeo"

OFFICIAL_PATH = RESOURCES / "official_floor_guide.json"
SECTION_MAP_PATH = RESOURCES / "category_section_map.json"
OUTPUT_PATH = RESOURCES / "store_category_by_name.json"
# id 기반 오버라이드. 시드에서 이름 매핑보다 **먼저** 적용되므로, 여기 남은 옛 값은
# 새 매핑을 조용히 이긴다(`studio_adapter._resolved_category`). 같은 원본으로 함께 맞춘다.
ID_MAP_PATH = RESOURCES / "store_categories.json"

# 공식과 도면이 같은 매장을 다르게 띄어 쓴다(`보테가베네타` vs `보테가 베네타`).
# 브랜드명 자체는 건드리지 않고 구분기호만 지워 맞춘다 — 글자를 지우면
# `CK 진`과 `CK진`이 아니라 `캘빈클라인 진`까지 같은 키가 되어 버린다.
_SEPARATORS = re.compile(r"[\s·・/(),.\-_&'\"]+")


def normalize(name: str | None) -> str:
    return _SEPARATORS.sub("", (name or "").lower())


def _studio_store_names() -> list[str]:
    """도면에 실제로 있는 매장 이름. 같은 이름이 여러 층에 있으면 그대로 중복된다."""
    names: list[str] = []
    for path in sorted(STUDIO_DIR.glob("stores_*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for store in payload.get("stores", []):
            name = (store.get("name") or "").strip()
            if name:
                names.append(name)
    return names


def build() -> tuple[dict[str, dict], Report]:
    """(매핑, 보고서)를 돌려준다. 보고서는 사람이 눈으로 확인할 잔여 항목이다."""
    official = json.loads(OFFICIAL_PATH.read_text(encoding="utf-8"))
    section_map = json.loads(SECTION_MAP_PATH.read_text(encoding="utf-8"))

    sections: dict[str, list[str]] = section_map["sections"]
    overrides: dict[str, list[str]] = {k: v for k, v in section_map["storeOverrides"].items() if not k.startswith("_")}
    local_only: dict[str, list[str]] = {k: v for k, v in section_map["localOnly"].items() if not k.startswith("_")}
    aliases: dict[str, str] = {k: v for k, v in section_map.get("aliases", {}).items() if not k.startswith("_")}

    # 기존 매핑은 버리지 않고 깔아 둔다. 공식이 싣지 않는 것(주차 구역 1A~,
    # 도면 전용 매장)이 여기에만 있어서, 통째로 갈아엎으면 그 매장들이 조용히
    # Studio 원본 카테고리로 떨어진다.
    carried = json.loads(OUTPUT_PATH.read_text(encoding="utf-8")) if OUTPUT_PATH.exists() else {}
    result: dict[str, dict] = dict(carried)

    studio_names = _studio_store_names()
    by_normalized: dict[str, list[str]] = {}
    for name in studio_names:
        by_normalized.setdefault(normalize(name), []).append(name)

    unknown_sections: list[str] = []
    unmatched_official: list[str] = []
    # 같은 이름이 여러 섹션에 있으면 나중에 만난 섹션이 이긴다 — 값이 조용히
    # 층 순서에 따라 정해지므로 눈에 보여야 한다(`POP-UP STUDIO`가 그렇다).
    seen_sections: dict[str, set[str]] = {}
    applied = 0

    for floor in official["floors"]:
        for section in floor["sections"]:
            title = section["title"]
            if title not in sections:
                unknown_sections.append(f"{floor['floor']} {title}")
                continue
            for brand in section["brands"]:
                pair = overrides.get(brand["name"]) or sections[title]
                lookup = aliases.get(brand["name"], brand["name"])
                targets = by_normalized.get(normalize(lookup))
                if not targets:
                    unmatched_official.append(f"{floor['floor']} {title} {brand['name']}")
                    continue
                seen_sections.setdefault(brand["name"], set()).add(title)
                for studio_name in dict.fromkeys(targets):
                    result[studio_name] = {"category": pair[0], "subcategory": pair[1]}
                    applied += 1

    # 도면에만 있는 매장은 공식으로 덮을 수 없어 손으로 적은 값이 마지막에 이긴다.
    for name, pair in local_only.items():
        result[name] = {"category": pair[0], "subcategory": pair[1]}

    studio_set = set(studio_names)
    report: Report = {
        "unknownSections": unknown_sections,
        "unmatchedOfficial": unmatched_official,
        # 도면에 없는데 매핑에만 남은 이름. 오래된 항목이라 지워도 되는지 확인용.
        "orphanEntries": sorted(name for name in result if name not in studio_set),
        "localOnlyMissing": sorted(name for name in local_only if name not in studio_set),
        # alias가 가리키는 도면 이름이 실제로 없으면 오타다 — 조용히 매칭 실패로
        # 흡수되면 "공식에만 있음"으로 잘못 보고된다.
        "aliasMissing": sorted(v for v in aliases.values() if v not in studio_set),
        "duplicateOfficialNames": sorted(
            f"{name}: {' / '.join(sorted(titles))}"
            for name, titles in seen_sections.items()
            if len(titles) > 1 and name not in overrides
        ),
        "appliedFromOfficial": applied,
    }
    return dict(sorted(result.items())), report


def reconcile_id_map(mapping: dict[str, dict]) -> list[str]:
    """id 오버라이드를 이름 매핑과 같은 값으로 맞춘다. 바뀐 항목 설명 목록을 돌려준다.

    이름이 매핑에 없는 항목은 건드리지 않는다 — 공식이 싣지 않은 매장이라
    덮을 근거가 없다.
    """
    id_map = json.loads(ID_MAP_PATH.read_text(encoding="utf-8"))
    changes: list[str] = []
    for entry in id_map.values():
        target = mapping.get((entry.get("name") or "").strip())
        if target is None:
            continue
        if (entry["category"], entry["subcategory"]) == (target["category"], target["subcategory"]):
            continue
        changes.append(
            f"{entry['name']}: {entry['category']}/{entry['subcategory']}"
            f" -> {target['category']}/{target['subcategory']}"
        )
        entry["category"] = target["category"]
        entry["subcategory"] = target["subcategory"]
    if changes:
        ID_MAP_PATH.write_text(json.dumps(id_map, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return changes


def main() -> None:
    mapping, report = build()

    if report["unknownSections"]:
        raise SystemExit(
            "매핑표에 없는 공식 섹션이 있다. category_section_map.json에 먼저 추가한다:\n  "
            + "\n  ".join(report["unknownSections"])
        )

    OUTPUT_PATH.write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    id_changes = reconcile_id_map(mapping)

    counts = Counter(v["category"] for v in mapping.values())
    print(f"{OUTPUT_PATH.name}: {len(mapping)}건 (공식에서 적용 {report['appliedFromOfficial']}건)")
    for category, n in counts.most_common():
        print(f"  {n:4}  {category}")
    print(f"\n{ID_MAP_PATH.name}에서 맞춘 항목 {len(id_changes)}건")
    for line in id_changes:
        print(f"  {line}")
    print(f"\n공식에 있으나 도면에서 못 찾음 {len(report['unmatchedOfficial'])}건")
    for line in report["unmatchedOfficial"]:
        print(f"  {line}")
    print(f"\n도면에 없는데 매핑에 남은 이름 {len(report['orphanEntries'])}건")
    for line in report["orphanEntries"]:
        print(f"  {line}")
    if report["duplicateOfficialNames"]:
        print(f"\n같은 이름이 여러 섹션에 있다 {len(report['duplicateOfficialNames'])}건 (뒤 섹션이 이긴다)")
        for line in report["duplicateOfficialNames"]:
            print(f"  {line}")
    if report["aliasMissing"]:
        print(f"\n⚠ alias가 가리키는 도면 이름이 없다 {len(report['aliasMissing'])}건")
        for line in report["aliasMissing"]:
            print(f"  {line}")
    if report["localOnlyMissing"]:
        print(f"\n⚠ localOnly에 적었지만 도면에 없는 이름 {len(report['localOnlyMissing'])}건")
        for line in report["localOnlyMissing"]:
            print(f"  {line}")


if __name__ == "__main__":
    main()
