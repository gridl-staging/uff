#!/usr/bin/env python3
"""
Stub summary for /Users/stuart/parallel_development/uff_dev/MAR18_workstream_B_polish_widget_keys_e2e/uff_dev/scripts/shoe_seg_normalize_to_coco.py.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path, PurePosixPath
from typing import Any, Callable

import cv2
import numpy as np
import shoe_seg_atr_adapter
import shoe_seg_openimages_adapter
import shoe_seg_stage6_workflow
from pycocotools import mask as mask_utils
REPO_ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = REPO_ROOT / "data/shoe_seg/raw"
UNIFIED_DIR = REPO_ROOT / "data/shoe_seg/unified"
UNIFIED_DIR.mkdir(parents=True, exist_ok=True)

DATASETS: list[dict[str, str]] = [
    {"name": "kaggle_shoe_seg", "raw_subdir": "kaggle_shoe_seg"},
    {"name": "kaggle_people_clothing", "raw_subdir": "kaggle_people_clothing"},
    {"name": "openimages_seg", "raw_subdir": "openimages_seg"},
    {"name": "modanet", "raw_subdir": "modanet_images"},
    {"name": "imaterialist", "raw_subdir": "imaterialist"},
    {"name": "ccp", "raw_subdir": "ccp"},
    {"name": "atr", "raw_subdir": "atr"},
]
SKIPPED_DATASETS: list[dict[str, str]] = [
    {
        "name": "fashionpedia",
        "reason": "No segmentation masks in HuggingFace version",
    },
    {
        "name": "deepfashion_masks",
        "reason": "No shoe categories",
    },
]
SHOE_CATEGORY = {"id": 1, "name": "shoe"}
DATASET_RAW_SUBDIR_BY_NAME = {
    dataset["name"]: dataset["raw_subdir"] for dataset in DATASETS
}
KAGGLE_SHOE_SEG_MASK_COLOR = (44, 153, 80)
KAGGLE_PEOPLE_SHOE_CLASS_ID = 39
KAGGLE_PEOPLE_IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".JPG", ".png")
CCP_SHOE_COLORS: list[tuple[int, int, int]] = [
    (70, 47, 124),
    (62, 72, 136),
    (54, 90, 140),
    (45, 111, 142),
    (34, 139, 141),
    (30, 155, 137),
    (37, 171, 129),
    (53, 183, 120),
    (83, 197, 103),
    (243, 229, 30),
]
IMAGE_FILE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".JPG", ".JPEG", ".PNG")
MASK_FILE_EXTENSIONS = (".png", ".PNG")
def _coerce_binary_mask(binary: np.ndarray) -> np.ndarray:
    if binary.ndim != 2:
        raise ValueError(f"Expected 2D binary mask, got shape={binary.shape}")
    return (binary > 0).astype(np.uint8)
def mask_to_polygons(binary: np.ndarray) -> list[list[int]]:
    mask = _coerce_binary_mask(binary)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    polygons: list[list[int]] = []
    for contour in contours:
        flattened = contour.flatten().tolist()
        if len(flattened) >= 6:
            polygons.append([int(value) for value in flattened])
    return polygons
def mask_to_rle(binary: np.ndarray) -> dict[str, Any]:
    mask = _coerce_binary_mask(binary)
    encoded = mask_utils.encode(np.asfortranarray(mask))
    counts = encoded["counts"]
    if isinstance(counts, bytes):
        counts = counts.decode("utf-8")
    return {"size": encoded["size"], "counts": counts}
def bbox_from_mask(binary: np.ndarray) -> list[int]:
    mask = _coerce_binary_mask(binary)
    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    if not rows.any() or not cols.any():
        raise ValueError("Cannot compute bbox from empty mask")
    y_min, y_max = np.where(rows)[0][[0, -1]]
    x_min, x_max = np.where(cols)[0][[0, -1]]
    return [int(x_min), int(y_min), int(x_max - x_min + 1), int(y_max - y_min + 1)]
def area_from_mask(binary: np.ndarray) -> int:
    return int(_coerce_binary_mask(binary).sum())
def make_image(id: int, file_name: str, width: int, height: int) -> dict[str, Any]:
    return {
        "id": int(id),
        "file_name": file_name,
        "width": int(width),
        "height": int(height),
    }
def make_annotation(
    id: int,
    image_id: int,
    segmentation: Any,
    bbox: list[int],
    area: int,
    iscrowd: int = 0,
) -> dict[str, Any]:
    """TODO: Document make_annotation."""
    return {
        "id": int(id),
        "image_id": int(image_id),
        "category_id": SHOE_CATEGORY["id"],
        "segmentation": segmentation,
        "bbox": [int(value) for value in bbox],
        "area": int(area),
        "iscrowd": int(iscrowd),
    }
def _validate_relative_file_name(file_name: str) -> None:
    """TODO: Document _validate_relative_file_name."""
    path = PurePosixPath(file_name)
    if not file_name:
        raise ValueError("file_name must not be empty")
    if path.is_absolute():
        raise ValueError(f"file_name must be relative, got absolute path: {file_name}")
    if path.parts[:3] == ("data", "shoe_seg", "raw"):
        raise ValueError(
            "file_name must be relative to data/shoe_seg/raw/ and must not include that prefix: "
            f"{file_name}"
        )
    if ".." in path.parts:
        raise ValueError(
            "file_name must stay within data/shoe_seg/raw/ and must not contain parent-directory segments: "
            f"{file_name}"
        )
def write_coco_json(
    images: list[dict[str, Any]],
    annotations: list[dict[str, Any]],
    output_path: Path,
) -> None:
    """TODO: Document write_coco_json."""
    image_ids = {image["id"] for image in images}
    for image in images:
        _validate_relative_file_name(image["file_name"])
    invalid_image_ids = sorted(
        {
            annotation["image_id"]
            for annotation in annotations
            if annotation["image_id"] not in image_ids
        }
    )
    if invalid_image_ids:
        raise ValueError(
            f"Annotations reference missing image_id values: {invalid_image_ids}"
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output = {
        "categories": [SHOE_CATEGORY],
        "images": images,
        "annotations": annotations,
    }
    with output_path.open("w", encoding="utf-8") as file:
        json.dump(output, file)
    print(
        f"Wrote {output_path} with {len(images)} images and {len(annotations)} annotations "
        f"for category '{SHOE_CATEGORY['name']}'"
    )
def check_inputs(dataset_names: tuple[str, ...] | None = None) -> None:
    """TODO: Document check_inputs."""
    missing_directories: list[str] = []
    datasets_to_check = DATASETS
    if dataset_names is not None:
        datasets_to_check = [
            {
                "name": dataset_name,
                "raw_subdir": DATASET_RAW_SUBDIR_BY_NAME[dataset_name],
            }
            for dataset_name in dataset_names
        ]
    for dataset in datasets_to_check:
        dataset_path = RAW_DIR / dataset["raw_subdir"]
        if not dataset_path.exists():
            missing_directories.append(f"{dataset['name']}: {dataset_path} (missing)")
            continue
        if not dataset_path.is_dir():
            missing_directories.append(
                f"{dataset['name']}: {dataset_path} (expected directory)"
            )
    for skipped in SKIPPED_DATASETS:
        print(f"Skipping {skipped['name']}: {skipped['reason']}")
    if missing_directories:
        message = ["Missing required dataset directories under RAW_DIR:"]
        message.extend(f"- {item}" for item in missing_directories)
        raise FileNotFoundError("\n".join(message))
def _iter_files(directory: Path, extensions: tuple[str, ...]) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(path for path in directory.iterdir() if path.suffix in extensions)
def _files_by_stem(
    directory: Path,
    extensions: tuple[str, ...],
    *,
    allowed_extensions: set[str] | None = None,
) -> dict[str, Path]:
    files_by_stem: dict[str, Path] = {}
    for path in _iter_files(directory, extensions):
        if allowed_extensions is not None and path.suffix not in allowed_extensions:
            continue
        files_by_stem.setdefault(path.stem, path)
    return files_by_stem
def _load_image_dimensions(image_path: Path) -> tuple[int, int] | None:
    image = cv2.imread(str(image_path), cv2.IMREAD_UNCHANGED)
    if image is None:
        return None
    height, width = image.shape[:2]
    return width, height
def _load_rgb_pixels(image_path: Path) -> np.ndarray | None:
    image = cv2.imread(str(image_path), cv2.IMREAD_UNCHANGED)
    if image is None:
        return None
    if image.ndim == 2:
        return cv2.cvtColor(image, cv2.COLOR_GRAY2RGB)
    if image.shape[2] == 4:
        return cv2.cvtColor(image, cv2.COLOR_BGRA2RGB)
    return cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
def _extract_binary_mask_for_colors(
    mask_rgb: np.ndarray, colors: list[tuple[int, int, int]]
) -> np.ndarray:
    binary = np.zeros(mask_rgb.shape[:2], dtype=np.uint8)
    for color in colors:
        matches = np.all(mask_rgb == np.array(color, dtype=np.uint8), axis=2)
        binary = np.maximum(binary, matches.astype(np.uint8))
    return binary
def _append_record_from_binary_mask(
    *,
    images: list[dict[str, Any]],
    annotations: list[dict[str, Any]],
    next_image_id: int,
    next_annotation_id: int,
    file_name: str,
    width: int,
    height: int,
    binary_mask: np.ndarray,
) -> tuple[int, int]:
    """TODO: Document _append_record_from_binary_mask."""
    area = area_from_mask(binary_mask)
    if area == 0:
        return next_image_id, next_annotation_id
    polygons = mask_to_polygons(binary_mask)
    if not polygons:
        return next_image_id, next_annotation_id
    bbox = bbox_from_mask(binary_mask)
    images.append(make_image(next_image_id, file_name, width, height))
    annotations.append(
        make_annotation(
            next_annotation_id,
            next_image_id,
            polygons,
            bbox,
            area,
        )
    )
    return next_image_id + 1, next_annotation_id + 1
def _append_record_for_image_path(
    *,
    images: list[dict[str, Any]],
    annotations: list[dict[str, Any]],
    next_image_id: int,
    next_annotation_id: int,
    image_path: Path,
    file_name: str,
    binary_mask: np.ndarray,
) -> tuple[int, int]:
    """TODO: Document _append_record_for_image_path."""
    dimensions = _load_image_dimensions(image_path)
    if dimensions is None:
        return next_image_id, next_annotation_id
    width, height = dimensions
    return _append_record_from_binary_mask(
        images=images,
        annotations=annotations,
        next_image_id=next_image_id,
        next_annotation_id=next_annotation_id,
        file_name=file_name,
        width=width,
        height=height,
        binary_mask=binary_mask,
    )
def build_kaggle_shoe_seg_records(
    dataset_dir: Path, start_image_id: int, start_annotation_id: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    """TODO: Document build_kaggle_shoe_seg_records."""
    images: list[dict[str, Any]] = []
    annotations: list[dict[str, Any]] = []
    next_image_id = start_image_id
    next_annotation_id = start_annotation_id
    for split in ("train", "valid"):
        images_dir = dataset_dir / f"shoes_dataset/{split}/images"
        masks_dir = dataset_dir / f"shoes_dataset/{split}/masks"
        masks_by_stem = _files_by_stem(masks_dir, MASK_FILE_EXTENSIONS)
        for image_path in _iter_files(images_dir, IMAGE_FILE_EXTENSIONS):
            mask_path = masks_by_stem.get(image_path.stem)
            if mask_path is None:
                continue
            mask_rgb = _load_rgb_pixels(mask_path)
            if mask_rgb is None:
                continue
            binary_mask = _extract_binary_mask_for_colors(
                mask_rgb, [KAGGLE_SHOE_SEG_MASK_COLOR]
            )
            file_name = f"kaggle_shoe_seg/shoes_dataset/{split}/images/{image_path.name}"
            next_image_id, next_annotation_id = _append_record_for_image_path(
                images=images,
                annotations=annotations,
                next_image_id=next_image_id,
                next_annotation_id=next_annotation_id,
                image_path=image_path,
                file_name=file_name,
                binary_mask=binary_mask,
            )
    return images, annotations, next_image_id, next_annotation_id
def build_kaggle_people_clothing_records(
    dataset_dir: Path, start_image_id: int, start_annotation_id: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    """TODO: Document build_kaggle_people_clothing_records."""
    images: list[dict[str, Any]] = []
    annotations: list[dict[str, Any]] = []
    next_image_id = start_image_id
    next_annotation_id = start_annotation_id
    images_dir = dataset_dir / "jpeg_images/IMAGES"
    masks_dir = dataset_dir / "png_masks/MASKS"
    images_by_stem = _files_by_stem(
        images_dir,
        IMAGE_FILE_EXTENSIONS,
        allowed_extensions=set(KAGGLE_PEOPLE_IMAGE_EXTENSIONS),
    )
    for mask_path in _iter_files(masks_dir, MASK_FILE_EXTENSIONS):
        if not mask_path.stem.startswith("seg_"):
            continue
        image_stem = f"img_{mask_path.stem.removeprefix('seg_')}"
        image_path = images_by_stem.get(image_stem)
        if image_path is None:
            continue
        mask_pixels = cv2.imread(str(mask_path), cv2.IMREAD_UNCHANGED)
        if mask_pixels is None:
            continue
        if mask_pixels.ndim == 3:
            mask_pixels = mask_pixels[:, :, 0]
        binary_mask = (mask_pixels == KAGGLE_PEOPLE_SHOE_CLASS_ID).astype(np.uint8)
        file_name = f"kaggle_people_clothing/jpeg_images/IMAGES/{image_path.name}"
        next_image_id, next_annotation_id = _append_record_for_image_path(
            images=images,
            annotations=annotations,
            next_image_id=next_image_id,
            next_annotation_id=next_annotation_id,
            image_path=image_path,
            file_name=file_name,
            binary_mask=binary_mask,
        )
    return images, annotations, next_image_id, next_annotation_id
def build_ccp_records(
    dataset_dir: Path, start_image_id: int, start_annotation_id: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    """TODO: Document build_ccp_records."""
    images: list[dict[str, Any]] = []
    annotations: list[dict[str, Any]] = []
    next_image_id = start_image_id
    next_annotation_id = start_annotation_id
    images_dir = dataset_dir / "images"
    masks_dir = dataset_dir / "labels/pixel_level_labels_colored"
    for mask_path in _iter_files(masks_dir, MASK_FILE_EXTENSIONS):
        image_path = images_dir / f"{mask_path.stem}.jpg"
        if not image_path.exists() or not image_path.is_file():
            continue
        mask_rgb = _load_rgb_pixels(mask_path)
        if mask_rgb is None:
            continue
        binary_mask = _extract_binary_mask_for_colors(mask_rgb, CCP_SHOE_COLORS)
        file_name = f"ccp/images/{image_path.name}"
        next_image_id, next_annotation_id = _append_record_for_image_path(
            images=images,
            annotations=annotations,
            next_image_id=next_image_id,
            next_annotation_id=next_annotation_id,
            image_path=image_path,
            file_name=file_name,
            binary_mask=binary_mask,
        )
    return images, annotations, next_image_id, next_annotation_id
AdapterBuilder = Callable[
    [Path, int, int], tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]
]
STAGE_2_ADAPTERS: dict[str, AdapterBuilder] = {
    "kaggle_shoe_seg": build_kaggle_shoe_seg_records,
    "kaggle_people_clothing": build_kaggle_people_clothing_records,
    "ccp": build_ccp_records,
}
def _run_adapters(
    adapters: dict[str, AdapterBuilder],
    raw_dir: Path,
    unified_dir: Path,
) -> dict[str, dict[str, int]]:
    """TODO: Document _run_adapters."""
    summaries: dict[str, dict[str, int]] = {}
    for dataset_name, adapter_builder in adapters.items():
        raw_subdir = DATASET_RAW_SUBDIR_BY_NAME[dataset_name]
        dataset_dir = raw_dir / raw_subdir
        images, annotations, _, _ = adapter_builder(dataset_dir, 1, 1)
        output_path = unified_dir / f"{dataset_name}.json"
        write_coco_json(images, annotations, output_path)
        summaries[dataset_name] = {
            "images": len(images),
            "annotations": len(annotations),
        }
    return summaries
def build_stage_2_outputs(
    raw_dir: Path | None = None, unified_dir: Path | None = None
) -> dict[str, dict[str, int]]:
    return _run_adapters(
        STAGE_2_ADAPTERS,
        raw_dir or RAW_DIR,
        unified_dir or UNIFIED_DIR,
    )
MODANET_SHOE_CATEGORY_IDS = {3, 4}  # boots=3, footwear=4
IMATERIALIST_SHOE_CLASS = 23
IMATERIALIST_IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png")
def _structured_relative_file_name(*parts: str) -> str:
    file_name = str(PurePosixPath(*parts))
    _validate_relative_file_name(file_name)
    return file_name
def _make_structured_image(
    image_id: int, file_name_parts: tuple[str, ...], width: int, height: int
) -> dict[str, Any]:
    return make_image(
        image_id,
        _structured_relative_file_name(*file_name_parts),
        width,
        height,
    )
def _remap_structured_annotation(
    *,
    annotation_id: int,
    image_id: int,
    segmentation: Any,
    bbox: list[float] | list[int],
    area: float | int,
    iscrowd: int = 0,
) -> dict[str, Any]:
    """TODO: Document _remap_structured_annotation."""
    return make_annotation(
        annotation_id,
        image_id,
        segmentation,
        [int(value) for value in bbox],
        int(area),
        iscrowd,
    )
def build_modanet_records(
    dataset_dir: Path, start_image_id: int, start_annotation_id: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    """TODO: Document build_modanet_records."""
    ann_path = dataset_dir / "datasets/coco/annotations/instances_all.json"
    with ann_path.open(encoding="utf-8") as f:
        coco_data = json.load(f)
    shoe_annotations = [
        ann for ann in coco_data["annotations"]
        if ann["category_id"] in MODANET_SHOE_CATEGORY_IDS
    ]
    shoe_image_ids = {ann["image_id"] for ann in shoe_annotations}
    shoe_source_images = [
        img for img in coco_data["images"] if img["id"] in shoe_image_ids
    ]
    old_to_new_image_id: dict[int, int] = {}
    images: list[dict[str, Any]] = []
    next_image_id = start_image_id
    for source_image in shoe_source_images:
        new_id = next_image_id
        old_to_new_image_id[source_image["id"]] = new_id
        images.append(
            _make_structured_image(
                new_id,
                (
                    "modanet_images",
                    "datasets",
                    "coco",
                    "images",
                    source_image["file_name"],
                ),
                source_image["width"],
                source_image["height"],
            )
        )
        next_image_id += 1
    annotations: list[dict[str, Any]] = []
    next_annotation_id = start_annotation_id
    for source_ann in shoe_annotations:
        new_image_id = old_to_new_image_id[source_ann["image_id"]]
        annotations.append(
            _remap_structured_annotation(
                annotation_id=next_annotation_id,
                image_id=new_image_id,
                segmentation=source_ann["segmentation"],
                bbox=source_ann["bbox"],
                area=source_ann["area"],
                iscrowd=source_ann.get("iscrowd", 0),
            )
        )
        next_annotation_id += 1
    return images, annotations, next_image_id, next_annotation_id
def _denormalize_yolo_polygon(
    normalized_coords: list[float], width: int, height: int
) -> list[float]:
    if len(normalized_coords) < 6 or len(normalized_coords) % 2 != 0:
        return []
    absolute: list[float] = []
    for i in range(0, len(normalized_coords), 2):
        absolute.append(normalized_coords[i] * width)
        absolute.append(normalized_coords[i + 1] * height)
    return absolute
def _polygon_area(polygon: list[float]) -> float:
    points = list(zip(polygon[0::2], polygon[1::2]))
    area = 0.0
    for index, (x1, y1) in enumerate(points):
        x2, y2 = points[(index + 1) % len(points)]
        area += (x1 * y2) - (x2 * y1)
    return abs(area) * 0.5
def _bbox_and_area_from_polygon(polygon: list[float]) -> tuple[list[float], float]:
    xs = polygon[0::2]
    ys = polygon[1::2]
    x_min, y_min = min(xs), min(ys)
    x_max, y_max = max(xs), max(ys)
    bbox = [x_min, y_min, x_max - x_min, y_max - y_min]
    area = _polygon_area(polygon)
    return bbox, area
def _resolve_imaterialist_image_path(image_dir: Path, stem: str) -> Path | None:
    for ext in IMATERIALIST_IMAGE_EXTENSIONS:
        candidate = image_dir / f"{stem}{ext}"
        if candidate.is_file():
            return candidate
    return None
def _parse_imaterialist_shoe_polygon(
    line: str, width: int, height: int
) -> list[float] | None:
    """TODO: Document _parse_imaterialist_shoe_polygon."""
    tokens = line.split()
    if len(tokens) < 7 or tokens[0] != str(IMATERIALIST_SHOE_CLASS):
        return None
    try:
        normalized_coords = [float(token) for token in tokens[1:]]
    except ValueError:
        return None
    if not all(math.isfinite(value) for value in normalized_coords):
        return None
    polygon = _denormalize_yolo_polygon(normalized_coords, width, height)
    if len(polygon) < 6:
        return None
    return polygon
def build_imaterialist_records(
    dataset_dir: Path, start_image_id: int, start_annotation_id: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    """TODO: Document build_imaterialist_records."""
    images: list[dict[str, Any]] = []
    annotations: list[dict[str, Any]] = []
    next_image_id = start_image_id
    next_annotation_id = start_annotation_id
    for split in ("train", "val"):
        label_dir = dataset_dir / "labels" / split
        image_dir = dataset_dir / "images" / split
        for label_path in _iter_files(label_dir, (".txt",)):
            image_path = _resolve_imaterialist_image_path(image_dir, label_path.stem)
            if image_path is None:
                continue
            label_lines = [
                line.strip()
                for line in label_path.read_text(encoding="utf-8").splitlines()
            ]
            dimensions = _load_image_dimensions(image_path)
            if dimensions is None:
                continue
            width, height = dimensions
            image_annotations: list[dict[str, Any]] = []
            for line in label_lines:
                polygon = _parse_imaterialist_shoe_polygon(line, width, height)
                if polygon is None:
                    continue
                bbox, area = _bbox_and_area_from_polygon(polygon)
                image_annotations.append(
                    _remap_structured_annotation(
                        annotation_id=next_annotation_id,
                        image_id=next_image_id,
                        segmentation=[polygon],
                        bbox=bbox,
                        area=area,
                    )
                )
                next_annotation_id += 1
            if not image_annotations:
                continue
            images.append(
                _make_structured_image(
                    next_image_id,
                    ("imaterialist", "images", split, image_path.name),
                    width,
                    height,
                )
            )
            annotations.extend(image_annotations)
            next_image_id += 1
    return images, annotations, next_image_id, next_annotation_id
STAGE_3_ADAPTERS: dict[str, AdapterBuilder] = {
    "modanet": build_modanet_records,
    "imaterialist": build_imaterialist_records,
}
def build_stage_3_outputs(
    raw_dir: Path | None = None, unified_dir: Path | None = None
) -> dict[str, dict[str, int]]:
    return _run_adapters(
        STAGE_3_ADAPTERS,
        raw_dir or RAW_DIR,
        unified_dir or UNIFIED_DIR,
    )
OPENIMAGES_SEG_SHOE_LABEL_IDS = shoe_seg_openimages_adapter.OPENIMAGES_SEG_SHOE_LABEL_IDS
def _resolve_openimages_mask_path(labels_dir: Path, mask_path: str) -> Path | None:
    return shoe_seg_openimages_adapter.resolve_openimages_mask_path(labels_dir, mask_path)
def _load_openimages_binary_mask(
    *, mask_path: Path, image_width: int, image_height: int
) -> np.ndarray | None:
    return shoe_seg_openimages_adapter.load_openimages_binary_mask(
        mask_path=mask_path,
        image_width=image_width,
        image_height=image_height,
        coerce_binary_mask=_coerce_binary_mask,
    )
def build_openimages_seg_records(
    dataset_dir: Path, start_image_id: int, start_annotation_id: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    """TODO: Document build_openimages_seg_records."""
    return shoe_seg_openimages_adapter.build_openimages_seg_records(
        dataset_dir,
        start_image_id,
        start_annotation_id,
        shoe_seg_openimages_adapter.OpenImagesAdapterDeps(
            load_image_dimensions=_load_image_dimensions,
            coerce_binary_mask=_coerce_binary_mask,
            area_from_mask=area_from_mask,
            bbox_from_mask=bbox_from_mask,
            mask_to_rle=mask_to_rle,
            make_image=make_image,
            make_annotation=make_annotation,
        ),
    )
STAGE_4_ADAPTERS: dict[str, AdapterBuilder] = {
    "openimages_seg": build_openimages_seg_records,
}
def build_stage_4_outputs(
    raw_dir: Path | None = None, unified_dir: Path | None = None
) -> dict[str, dict[str, int]]:
    return _run_adapters(
        STAGE_4_ADAPTERS,
        raw_dir or RAW_DIR,
        unified_dir or UNIFIED_DIR,
    )
def build_atr_records(
    dataset_dir: Path, start_image_id: int, start_annotation_id: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    """TODO: Document build_atr_records."""
    return shoe_seg_atr_adapter.build_atr_records(
        dataset_dir,
        start_image_id,
        start_annotation_id,
        shoe_seg_atr_adapter.AtrAdapterDeps(
            iter_atr_rows=shoe_seg_atr_adapter._iter_atr_parquet_rows,
            load_atr_row_image_and_mask=(
                shoe_seg_atr_adapter._load_atr_row_image_and_mask
            ),
            mask_to_polygons=mask_to_polygons,
            bbox_from_mask=bbox_from_mask,
            area_from_mask=area_from_mask,
            make_image=make_image,
            make_annotation=make_annotation,
            write_rgb_jpg=shoe_seg_atr_adapter._write_rgb_jpg,
        ),
    )
STAGE_5_ADAPTERS: dict[str, AdapterBuilder] = {
    "atr": build_atr_records,
}
def build_stage_5_outputs(
    raw_dir: Path | None = None, unified_dir: Path | None = None
) -> dict[str, dict[str, int]]:
    return _run_adapters(
        STAGE_5_ADAPTERS,
        raw_dir or RAW_DIR,
        unified_dir or UNIFIED_DIR,
    )
def _dataset_output_names() -> list[str]:
    return [dataset["name"] for dataset in DATASETS]
def _dataset_split_prefixes() -> list[str]:
    return [dataset["raw_subdir"] for dataset in DATASETS]
def validate_coco_output(output_path: Path) -> None:
    shoe_seg_stage6_workflow.validate_coco_output(
        output_path=output_path,
        expected_category=SHOE_CATEGORY,
        validate_relative_file_name=_validate_relative_file_name,
    )
def validate_per_dataset_outputs(unified_dir: Path | None = None) -> list[Path]:
    return shoe_seg_stage6_workflow.validate_per_dataset_outputs(
        unified_dir=unified_dir or UNIFIED_DIR,
        dataset_names=_dataset_output_names(),
        validate_coco_output_fn=validate_coco_output,
    )
def merge_dataset_outputs(
    unified_dir: Path | None = None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    return shoe_seg_stage6_workflow.merge_dataset_outputs(
        unified_dir or UNIFIED_DIR,
        _dataset_output_names(),
    )
def _build_split_membership(images: list[dict[str, Any]]) -> dict[str, list[int]]:
    return shoe_seg_stage6_workflow.build_split_membership(
        images,
        _dataset_split_prefixes(),
        seed=42,
    )
def write_split_outputs(
    *,
    images: list[dict[str, Any]],
    annotations: list[dict[str, Any]],
    unified_dir: Path | None = None,
) -> dict[str, dict[str, int]]:
    return shoe_seg_stage6_workflow.write_split_outputs(
        images=images,
        annotations=annotations,
        unified_dir=unified_dir or UNIFIED_DIR,
        build_split_membership_fn=_build_split_membership,
        write_coco_json_fn=write_coco_json,
    )
def main() -> int:
    """TODO: Document main."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Run fail-fast input validation and exit without processing datasets.",
    )
    args = parser.parse_args()
    if args.check:
        check_inputs()
        print("Input checks passed.")
        return 0
    active_datasets = (
        tuple(STAGE_2_ADAPTERS)
        + tuple(STAGE_3_ADAPTERS)
        + tuple(STAGE_4_ADAPTERS)
        + tuple(STAGE_5_ADAPTERS)
    )
    check_inputs(active_datasets)
    for stage_label, build_fn in [
        ("Stage 2", build_stage_2_outputs),
        ("Stage 3", build_stage_3_outputs),
        ("Stage 4", build_stage_4_outputs),
        ("Stage 5", build_stage_5_outputs),
    ]:
        summaries = build_fn()
        for dataset_name, counts in summaries.items():
            print(
                f"{stage_label} built {dataset_name}: "
                f"{counts['images']} images, {counts['annotations']} annotations"
            )
    validate_per_dataset_outputs()
    merged_images, merged_annotations = merge_dataset_outputs()
    print(
        f"Stage 6 merged outputs: {len(merged_images)} images, "
        f"{len(merged_annotations)} annotations"
    )
    split_summaries = write_split_outputs(images=merged_images, annotations=merged_annotations)
    for split_name, counts in split_summaries.items():
        print(
            f"Stage 6 wrote split_{split_name}.json: "
            f"{counts['images']} images, {counts['annotations']} annotations"
        )
    return 0
if __name__ == "__main__":
    raise SystemExit(main())
