from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path

import cv2
import numpy as np

SCRIPT_PATH = Path(__file__).resolve().parent / "shoe_seg_normalize_to_coco.py"


def load_module():
    script_dir = str(SCRIPT_PATH.parent)
    if script_dir not in sys.path:
        sys.path.insert(0, script_dir)

    spec = importlib.util.spec_from_file_location(
        "shoe_seg_normalize_to_coco_under_test", SCRIPT_PATH
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ShoeSegNormalizeToCocoTestBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def _create_dataset_roots(
        self, raw_dir: Path, dataset_names: list[str] | None = None
    ) -> None:
        module = self.module
        if dataset_names is None:
            dataset_names = [dataset["name"] for dataset in module.DATASETS]
        for dataset_name in dataset_names:
            (raw_dir / module.DATASET_RAW_SUBDIR_BY_NAME[dataset_name]).mkdir(
                parents=True,
                exist_ok=True,
            )

    def _dataset_output_json_names(self) -> list[str]:
        return [f"{dataset['name']}.json" for dataset in self.module.DATASETS]

    @staticmethod
    def _write_raw_coco_json(
        output_path: Path,
        *,
        categories: list[dict[str, object]],
        images: list[dict[str, object]],
        annotations: list[dict[str, object]],
    ) -> None:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "categories": categories,
            "images": images,
            "annotations": annotations,
        }
        output_path.write_text(json.dumps(payload), encoding="utf-8")

    @staticmethod
    def _write_jpg(path: Path, width: int, height: int) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        image = np.full((height, width, 3), 127, dtype=np.uint8)
        cv2.imwrite(str(path), image)

    @staticmethod
    def _write_rgb_png(path: Path, rgb: np.ndarray) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        cv2.imwrite(str(path), bgr)

    @staticmethod
    def _write_gray_png(path: Path, pixels: np.ndarray) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(path), pixels)

    @staticmethod
    def _write_modanet_coco_json(
        annotations_path: Path,
        images: list[dict[str, object]],
        annotations: list[dict[str, object]],
        categories: list[dict[str, object]],
    ) -> None:
        annotations_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "images": images,
            "annotations": annotations,
            "categories": categories,
        }
        annotations_path.write_text(json.dumps(payload), encoding="utf-8")

    @staticmethod
    def _write_yolo_label(path: Path, lines: list[str]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
