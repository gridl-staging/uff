from __future__ import annotations
"""
Stub summary for /Users/stuart/parallel_development/uff_dev/MAR18_workstream_B_polish_widget_keys_e2e/uff_dev/scripts/shoe_seg_stage6_workflow.py.
"""

import json
import random
from pathlib import Path, PurePosixPath
from typing import Any, Callable


def _validate_dataset_name(dataset_name: str) -> str:
    path = PurePosixPath(dataset_name)
    if (
        not dataset_name
        or path.is_absolute()
        or len(path.parts) != 1
        or ".." in path.parts
        or "\\" in dataset_name
    ):
        raise ValueError(
            f"dataset_name must be a simple relative name without path separators: {dataset_name!r}"
        )
    return dataset_name


def dataset_output_paths(unified_dir: Path, dataset_names: list[str]) -> list[Path]:
    return [
        unified_dir / f"{_validate_dataset_name(dataset_name)}.json"
        for dataset_name in dataset_names
    ]


def load_coco_json(output_path: Path) -> dict[str, Any]:
    with output_path.open(encoding="utf-8") as file:
        return json.load(file)


def _require_object_list(
    payload: dict[str, Any], *, output_path: Path, field_name: str
) -> list[dict[str, Any]]:
    records = payload.get(field_name)
    if not isinstance(records, list):
        raise ValueError(f"{output_path} must contain a list field '{field_name}'")
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            raise ValueError(
                f"{output_path} has non-object entry at {field_name}[{index}]"
            )
    return records


def _require_record_field(
    record: dict[str, Any], *, output_path: Path, record_name: str, field_name: str
) -> Any:
    if field_name not in record:
        raise ValueError(
            f"{output_path} {record_name} is missing required field '{field_name}'"
        )
    return record[field_name]


def _load_required_object_lists(
    output_path: Path, *field_names: str
) -> list[list[dict[str, Any]]]:
    payload = load_coco_json(output_path)
    if not isinstance(payload, dict):
        raise ValueError(f"{output_path} must contain a top-level JSON object")
    return [
        _require_object_list(payload, output_path=output_path, field_name=field_name)
        for field_name in field_names
    ]


def _image_field(image: dict[str, Any], *, output_path: Path, field_name: str) -> Any:
    return _require_record_field(
        image,
        output_path=output_path,
        record_name="image",
        field_name=field_name,
    )


def _annotation_field(
    annotation: dict[str, Any], *, output_path: Path, field_name: str
) -> Any:
    return _require_record_field(
        annotation,
        output_path=output_path,
        record_name="annotation",
        field_name=field_name,
    )


def _remap_image_record(
    image: dict[str, Any], *, output_path: Path, new_image_id: int
) -> tuple[int, dict[str, Any]]:
    """TODO: Document _remap_image_record."""
    source_image_id = _image_field(image, output_path=output_path, field_name="id")
    remapped_image = {
        "id": new_image_id,
        "file_name": _image_field(
            image,
            output_path=output_path,
            field_name="file_name",
        ),
        "width": int(
            _image_field(
                image,
                output_path=output_path,
                field_name="width",
            )
        ),
        "height": int(
            _image_field(
                image,
                output_path=output_path,
                field_name="height",
            )
        ),
    }
    return source_image_id, remapped_image


def _remap_annotation_record(
    annotation: dict[str, Any],
    *,
    output_path: Path,
    new_annotation_id: int,
    image_id_map: dict[int, int],
) -> dict[str, Any]:
    """TODO: Document _remap_annotation_record."""
    source_image_id = _annotation_field(
        annotation,
        output_path=output_path,
        field_name="image_id",
    )
    remapped_image_id = image_id_map.get(source_image_id)
    if remapped_image_id is None:
        raise ValueError(
            f"{output_path} has annotations with missing image_id values: [{source_image_id}]"
        )

    return {
        "id": new_annotation_id,
        "image_id": remapped_image_id,
        "category_id": _annotation_field(
            annotation,
            output_path=output_path,
            field_name="category_id",
        ),
        "segmentation": _annotation_field(
            annotation,
            output_path=output_path,
            field_name="segmentation",
        ),
        "bbox": _annotation_field(
            annotation,
            output_path=output_path,
            field_name="bbox",
        ),
        "area": _annotation_field(
            annotation,
            output_path=output_path,
            field_name="area",
        ),
        "iscrowd": annotation.get("iscrowd", 0),
    }


def validate_coco_output(
    *,
    output_path: Path,
    expected_category: dict[str, Any],
    validate_relative_file_name: Callable[[str], None],
) -> None:
    """TODO: Document validate_coco_output."""
    categories, images, annotations = _load_required_object_lists(
        output_path,
        "categories",
        "images",
        "annotations",
    )
    if categories != [expected_category]:
        raise ValueError(
            f"{output_path} has categories={categories}, expected {[expected_category]}"
        )
    if not images:
        raise ValueError(f"{output_path} must contain at least one image")
    if not annotations:
        raise ValueError(f"{output_path} must contain at least one annotation")

    image_ids: set[int] = set()
    for image in images:
        image_id = _image_field(image, output_path=output_path, field_name="id")
        file_name = _image_field(
            image,
            output_path=output_path,
            field_name="file_name",
        )
        if not isinstance(file_name, str):
            raise ValueError(f"{output_path} image file_name must be a string")
        image_ids.add(image_id)
        validate_relative_file_name(file_name)

    invalid_image_ids = {
        image_id
        for annotation in annotations
        if (
            image_id := _annotation_field(
                annotation,
                output_path=output_path,
                field_name="image_id",
            )
        )
        not in image_ids
    }
    if invalid_image_ids:
        raise ValueError(
            f"{output_path} has annotations with missing image_id values: {sorted(invalid_image_ids)}"
        )
    expected_category_id = expected_category["id"]
    if any(
        _annotation_field(
            annotation,
            output_path=output_path,
            field_name="category_id",
        ) != expected_category_id
        for annotation in annotations
    ):
        raise ValueError(f"{output_path} has category drift in annotations")


def validate_per_dataset_outputs(
    *,
    unified_dir: Path,
    dataset_names: list[str],
    validate_coco_output_fn: Callable[[Path], None],
) -> list[Path]:
    """TODO: Document validate_per_dataset_outputs."""
    expected_paths = dataset_output_paths(unified_dir, dataset_names)
    missing = [path for path in expected_paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(
            "Missing expected per-dataset JSON outputs:\n- "
            + "\n- ".join(map(str, missing))
        )
    for path in expected_paths:
        validate_coco_output_fn(path)
    return expected_paths


def merge_dataset_outputs(
    unified_dir: Path, dataset_names: list[str]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """TODO: Document merge_dataset_outputs."""
    merged_images: list[dict[str, Any]] = []
    merged_annotations: list[dict[str, Any]] = []
    next_image_id = 1
    next_annotation_id = 1
    for output_path in dataset_output_paths(unified_dir, dataset_names):
        images, annotations = _load_required_object_lists(
            output_path,
            "images",
            "annotations",
        )
        old_to_new_image_id: dict[int, int] = {}

        for image in images:
            source_image_id, remapped_image = _remap_image_record(
                image,
                output_path=output_path,
                new_image_id=next_image_id,
            )
            old_to_new_image_id[source_image_id] = next_image_id
            merged_images.append(remapped_image)
            next_image_id += 1

        for annotation in annotations:
            merged_annotations.append(
                _remap_annotation_record(
                    annotation,
                    output_path=output_path,
                    new_annotation_id=next_annotation_id,
                    image_id_map=old_to_new_image_id,
                )
            )
            next_annotation_id += 1
    return merged_images, merged_annotations


def build_split_membership(
    images: list[dict[str, Any]],
    dataset_prefix_order: list[str],
    seed: int = 42,
) -> dict[str, list[int]]:
    """TODO: Document build_split_membership."""
    dataset_rank = {
        dataset_prefix: index for index, dataset_prefix in enumerate(dataset_prefix_order)
    }
    ordered_ids = [
        image["id"]
        for image in sorted(
            images,
            key=lambda image: (
                dataset_rank.get(PurePosixPath(image["file_name"]).parts[0], len(dataset_rank)),
                image["file_name"],
                image["id"],
            ),
        )
    ]
    random.Random(seed).shuffle(ordered_ids)
    train_cutoff = int(len(ordered_ids) * 0.8)
    val_cutoff = train_cutoff + int(len(ordered_ids) * 0.1)
    return {
        "train": ordered_ids[:train_cutoff],
        "val": ordered_ids[train_cutoff:val_cutoff],
        "test": ordered_ids[val_cutoff:],
    }


def write_split_outputs(
    *,
    images: list[dict[str, Any]],
    annotations: list[dict[str, Any]],
    unified_dir: Path,
    build_split_membership_fn: Callable[[list[dict[str, Any]]], dict[str, list[int]]],
    write_coco_json_fn: Callable[[list[dict[str, Any]], list[dict[str, Any]], Path], None],
) -> dict[str, dict[str, int]]:
    """TODO: Document write_split_outputs."""
    split_membership = build_split_membership_fn(images)
    split_summaries: dict[str, dict[str, int]] = {}
    for split_name in ("train", "val", "test"):
        image_ids = set(split_membership[split_name])
        split_images = [image for image in images if image["id"] in image_ids]
        split_annotations = [annotation for annotation in annotations if annotation["image_id"] in image_ids]
        output_path = unified_dir / f"split_{split_name}.json"
        write_coco_json_fn(split_images, split_annotations, output_path)
        split_summaries[split_name] = {"images": len(split_images), "annotations": len(split_annotations)}
    return split_summaries
