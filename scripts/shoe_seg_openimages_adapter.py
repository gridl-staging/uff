from __future__ import annotations
"""
Stub summary for /Users/stuart/parallel_development/uff_dev/MAR18_workstream_B_polish_widget_keys_e2e/uff_dev/scripts/shoe_seg_openimages_adapter.py.
"""

import csv
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Callable, Optional

import cv2
import numpy as np

OPENIMAGES_SEG_SHOE_LABEL_IDS = {"/m/01b638", "/m/06k2mb"}

LoadImageDimensions = Callable[[Path], Optional[tuple[int, int]]]
CoerceBinaryMask = Callable[[np.ndarray], np.ndarray]
AreaFromMask = Callable[[np.ndarray], int]
BboxFromMask = Callable[[np.ndarray], list[int]]
MaskToRle = Callable[[np.ndarray], dict[str, Any]]
MakeImage = Callable[[int, str, int, int], dict[str, Any]]
MakeAnnotation = Callable[[int, int, Any, list[int], int], dict[str, Any]]


@dataclass(frozen=True)
class OpenImagesAdapterDeps:
    load_image_dimensions: LoadImageDimensions
    coerce_binary_mask: CoerceBinaryMask
    area_from_mask: AreaFromMask
    bbox_from_mask: BboxFromMask
    mask_to_rle: MaskToRle
    make_image: MakeImage
    make_annotation: MakeAnnotation


def resolve_openimages_mask_path(labels_dir: Path, mask_path: str) -> Path | None:
    """TODO: Document resolve_openimages_mask_path."""
    mask_parts = PurePosixPath(mask_path).parts
    if not mask_parts or mask_parts[0] == "/" or ".." in mask_parts:
        return None

    masks_root = labels_dir / "masks"
    relative_mask_path = Path(*mask_parts)
    direct_candidate = masks_root / relative_mask_path
    if direct_candidate.is_file():
        return direct_candidate

    first_part = mask_parts[0]
    alternate_first_parts: list[str] = []
    for candidate in (first_part.lower(), first_part.upper()):
        if candidate != first_part:
            alternate_first_parts.append(candidate)
    for alternate_first in alternate_first_parts:
        alternate_candidate = masks_root / Path(alternate_first, *mask_parts[1:])
        if alternate_candidate.is_file():
            return alternate_candidate

    if len(mask_parts) == 1 and mask_parts[0]:
        file_name = mask_parts[0]
        for prefix in (file_name[0].lower(), file_name[0].upper()):
            candidate = masks_root / prefix / file_name
            if candidate.is_file():
                return candidate

    return None


def load_openimages_binary_mask(
    *,
    mask_path: Path,
    image_width: int,
    image_height: int,
    coerce_binary_mask: CoerceBinaryMask,
) -> np.ndarray | None:
    """TODO: Document load_openimages_binary_mask."""
    mask_pixels = cv2.imread(str(mask_path), cv2.IMREAD_UNCHANGED)
    if mask_pixels is None:
        return None

    if mask_pixels.ndim == 3:
        if mask_pixels.shape[2] == 4:
            mask_pixels = cv2.cvtColor(mask_pixels, cv2.COLOR_BGRA2GRAY)
        else:
            mask_pixels = cv2.cvtColor(mask_pixels, cv2.COLOR_BGR2GRAY)

    if mask_pixels.shape[0] != image_height or mask_pixels.shape[1] != image_width:
        mask_pixels = cv2.resize(
            mask_pixels,
            (image_width, image_height),
            interpolation=cv2.INTER_NEAREST,
        )

    return coerce_binary_mask(mask_pixels)


def build_openimages_seg_records(
    dataset_dir: Path,
    start_image_id: int,
    start_annotation_id: int,
    deps: OpenImagesAdapterDeps,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    """TODO: Document build_openimages_seg_records."""
    images: list[dict[str, Any]] = []
    annotations: list[dict[str, Any]] = []
    image_record_ids: dict[tuple[str, str], int] = {}
    next_image_id = start_image_id
    next_annotation_id = start_annotation_id

    for split in ("train", "validation"):
        split_root = dataset_dir / "open-images-v7" / split
        labels_dir = split_root / "labels"
        csv_path = labels_dir / "segmentations.csv"
        if not csv_path.is_file():
            continue

        with csv_path.open(encoding="utf-8", newline="") as csv_file:
            reader = csv.DictReader(csv_file)
            for row in reader:
                label_name = (row.get("LabelName") or "").strip()
                if label_name not in OPENIMAGES_SEG_SHOE_LABEL_IDS:
                    continue

                image_id = (row.get("ImageID") or "").strip()
                mask_rel_path = (row.get("MaskPath") or "").strip()
                if not image_id or not mask_rel_path:
                    continue

                image_path = split_root / "data" / f"{image_id}.jpg"
                if not image_path.is_file():
                    continue
                dimensions = deps.load_image_dimensions(image_path)
                if dimensions is None:
                    continue
                width, height = dimensions

                mask_path = resolve_openimages_mask_path(labels_dir, mask_rel_path)
                if mask_path is None:
                    continue

                binary_mask = load_openimages_binary_mask(
                    mask_path=mask_path,
                    image_width=width,
                    image_height=height,
                    coerce_binary_mask=deps.coerce_binary_mask,
                )
                if binary_mask is None:
                    continue

                area = deps.area_from_mask(binary_mask)
                if area == 0:
                    continue

                bbox = deps.bbox_from_mask(binary_mask)
                split_image_key = (split, image_id)
                record_image_id = image_record_ids.get(split_image_key)
                if record_image_id is None:
                    record_image_id = next_image_id
                    image_record_ids[split_image_key] = record_image_id
                    images.append(
                        deps.make_image(
                            record_image_id,
                            f"openimages_seg/open-images-v7/{split}/data/{image_id}.jpg",
                            width,
                            height,
                        )
                    )
                    next_image_id += 1

                annotations.append(
                    deps.make_annotation(
                        next_annotation_id,
                        record_image_id,
                        deps.mask_to_rle(binary_mask),
                        bbox,
                        area,
                    )
                )
                next_annotation_id += 1

    return images, annotations, next_image_id, next_annotation_id
