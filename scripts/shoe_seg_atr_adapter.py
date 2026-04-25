from __future__ import annotations
"""
Stub summary for /Users/stuart/parallel_development/uff_dev/MAR18_workstream_B_polish_widget_keys_e2e/uff_dev/scripts/shoe_seg_atr_adapter.py.
"""

from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any, Callable, Iterable, Iterator, Mapping, Optional

import cv2
import numpy as np

ATR_SHOE_CLASS_IDS = {9, 10}

IterAtrRows = Callable[[Path], Iterable[Mapping[str, Any]]]
LoadAtrRowImageAndMask = Callable[
    [Mapping[str, Any]], Optional[tuple[np.ndarray, np.ndarray]]
]
MaskToPolygons = Callable[[np.ndarray], list[list[int]]]
BboxFromMask = Callable[[np.ndarray], list[int]]
AreaFromMask = Callable[[np.ndarray], int]
MakeImage = Callable[[int, str, int, int], dict[str, Any]]
MakeAnnotation = Callable[[int, int, Any, list[int], int], dict[str, Any]]
WriteRgbJpg = Callable[[Path, np.ndarray], bool]


@dataclass(frozen=True)
class AtrAdapterDeps:
    iter_atr_rows: IterAtrRows
    load_atr_row_image_and_mask: LoadAtrRowImageAndMask
    mask_to_polygons: MaskToPolygons
    bbox_from_mask: BboxFromMask
    area_from_mask: AreaFromMask
    make_image: MakeImage
    make_annotation: MakeAnnotation
    write_rgb_jpg: WriteRgbJpg


def _import_pandas():
    try:
        import pandas
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "ATR adapter requires pandas with parquet support. Install pandas and pyarrow."
        ) from exc
    return pandas


def _import_pillow_image():
    try:
        from PIL import Image
    except ModuleNotFoundError as exc:
        raise RuntimeError("ATR adapter requires Pillow to decode ATR image payloads.") from exc
    return Image


def _decode_atr_payload_bytes(payload: Any) -> bytes | None:
    if isinstance(payload, bytes):
        return payload
    if isinstance(payload, bytearray):
        return bytes(payload)
    if isinstance(payload, memoryview):
        return payload.tobytes()
    if isinstance(payload, dict):
        return _decode_atr_payload_bytes(payload.get("bytes"))
    return None


def _iter_atr_parquet_rows(data_dir: Path) -> Iterator[dict[str, Any]]:
    pandas = _import_pandas()

    for parquet_path in sorted(data_dir.glob("*.parquet")):
        frame = pandas.read_parquet(parquet_path)
        for row in frame.to_dict(orient="records"):
            yield row


def _load_atr_row_image_and_mask(
    row: Mapping[str, Any],
) -> tuple[np.ndarray, np.ndarray] | None:
    """TODO: Document _load_atr_row_image_and_mask."""
    image_bytes = _decode_atr_payload_bytes(row.get("image"))
    mask_bytes = _decode_atr_payload_bytes(row.get("mask"))
    if image_bytes is None or mask_bytes is None:
        return None

    image_loader = _import_pillow_image()
    try:
        with image_loader.open(BytesIO(image_bytes)) as source_image:
            image_rgb = np.array(source_image.convert("RGB"), dtype=np.uint8)
        with image_loader.open(BytesIO(mask_bytes)) as source_mask:
            mask_pixels = np.array(source_mask.convert("L"), dtype=np.uint8)
    except Exception:
        return None

    if image_rgb.ndim != 3 or image_rgb.shape[2] != 3:
        return None
    if mask_pixels.ndim != 2:
        return None
    if mask_pixels.shape != image_rgb.shape[:2]:
        mask_pixels = cv2.resize(
            mask_pixels,
            (image_rgb.shape[1], image_rgb.shape[0]),
            interpolation=cv2.INTER_NEAREST,
        )

    return image_rgb, mask_pixels


def _write_rgb_jpg(path: Path, image_rgb: np.ndarray) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    if image_rgb.ndim != 3 or image_rgb.shape[2] != 3:
        return False

    image_bgr = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2BGR)
    return bool(cv2.imwrite(str(path), image_bgr))


def _merge_shoe_mask_classes(mask_pixels: np.ndarray) -> np.ndarray:
    if mask_pixels.ndim == 3:
        mask_pixels = mask_pixels[:, :, 0]
    return np.isin(mask_pixels, tuple(ATR_SHOE_CLASS_IDS)).astype(np.uint8)


def _build_atr_row_records(
    *,
    row: Mapping[str, Any],
    image_id: int,
    annotation_id: int,
    extracted_images_dir: Path,
    deps: AtrAdapterDeps,
) -> tuple[dict[str, Any], dict[str, Any]] | None:
    """TODO: Document _build_atr_row_records."""
    loaded_row = deps.load_atr_row_image_and_mask(row)
    if loaded_row is None:
        return None

    image_rgb, mask_pixels = loaded_row
    if image_rgb.size == 0 or mask_pixels.size == 0:
        return None

    shoe_binary_mask = _merge_shoe_mask_classes(mask_pixels)
    area = deps.area_from_mask(shoe_binary_mask)
    if area == 0:
        return None

    polygons = deps.mask_to_polygons(shoe_binary_mask)
    if not polygons:
        return None

    image_file_name = f"atr_{image_id}.jpg"
    extracted_path = extracted_images_dir / image_file_name
    if not deps.write_rgb_jpg(extracted_path, image_rgb):
        return None

    height, width = image_rgb.shape[:2]
    image = deps.make_image(
        image_id,
        f"atr/extracted_images/{image_file_name}",
        width,
        height,
    )
    annotation = deps.make_annotation(
        annotation_id,
        image_id,
        polygons,
        deps.bbox_from_mask(shoe_binary_mask),
        area,
    )
    return image, annotation


def build_atr_records(
    dataset_dir: Path,
    start_image_id: int,
    start_annotation_id: int,
    deps: AtrAdapterDeps,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    """TODO: Document build_atr_records."""
    images: list[dict[str, Any]] = []
    annotations: list[dict[str, Any]] = []
    next_image_id = start_image_id
    next_annotation_id = start_annotation_id

    data_dir = dataset_dir / "data"
    extracted_images_dir = dataset_dir / "extracted_images"
    extracted_images_dir.mkdir(parents=True, exist_ok=True)

    for row in deps.iter_atr_rows(data_dir):
        records = _build_atr_row_records(
            row=row,
            image_id=next_image_id,
            annotation_id=next_annotation_id,
            extracted_images_dir=extracted_images_dir,
            deps=deps,
        )
        if records is None:
            continue

        image, annotation = records
        images.append(image)
        annotations.append(annotation)
        next_image_id += 1
        next_annotation_id += 1

    return images, annotations, next_image_id, next_annotation_id
