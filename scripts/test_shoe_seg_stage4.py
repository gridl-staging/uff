from __future__ import annotations

import csv
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

from test_shoe_seg_test_support import ShoeSegNormalizeToCocoTestBase


class Stage4OpenImagesAdapterTests(ShoeSegNormalizeToCocoTestBase):
    """Tests for Stage 4 Open Images helper, adapter, and orchestration seams."""

    @staticmethod
    def _write_openimages_segmentations_csv(csv_path: Path, rows: list[dict[str, str]]) -> None:
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        with csv_path.open("w", encoding="utf-8", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=["ImageID", "LabelName", "MaskPath"])
            writer.writeheader()
            writer.writerows(rows)

    def test_openimages_shoe_label_ids_match_stage4_pinned_values(self):
        module = self.module

        self.assertEqual(
            module.OPENIMAGES_SEG_SHOE_LABEL_IDS,
            {"/m/01b638", "/m/06k2mb"},
        )

    def test_resolve_openimages_mask_path_uses_upper_lower_hex_prefix_fallback(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            labels_dir = Path(tmp_dir) / "labels"

            upper_mask = labels_dir / "masks/A/abc123.png"
            self._write_gray_png(upper_mask, np.array([[0, 255], [255, 0]], dtype=np.uint8))

            lower_mask = labels_dir / "masks/f/fed456.png"
            self._write_gray_png(lower_mask, np.array([[0, 255], [255, 0]], dtype=np.uint8))

            resolved_upper = module._resolve_openimages_mask_path(
                labels_dir, "a/abc123.png"
            )
            resolved_lower = module._resolve_openimages_mask_path(
                labels_dir, "F/fed456.png"
            )

            self.assertIsNotNone(resolved_upper)
            self.assertIsNotNone(resolved_lower)
            self.assertTrue(resolved_upper.is_file())
            self.assertTrue(resolved_lower.is_file())
            self.assertEqual(resolved_upper.name, upper_mask.name)
            self.assertEqual(resolved_lower.name, lower_mask.name)

    def test_load_openimages_binary_mask_resizes_nearest_and_stays_2d_binary(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            mask_path = Path(tmp_dir) / "mask.png"
            self._write_gray_png(
                mask_path,
                np.array(
                    [
                        [0, 255],
                        [255, 0],
                    ],
                    dtype=np.uint8,
                ),
            )

            binary = module._load_openimages_binary_mask(
                mask_path=mask_path,
                image_width=4,
                image_height=4,
            )

            self.assertEqual(binary.ndim, 2)
            self.assertEqual(binary.shape, (4, 4))
            self.assertEqual(set(np.unique(binary).tolist()), {0, 1})

            expected = np.array(
                [
                    [0, 0, 1, 1],
                    [0, 0, 1, 1],
                    [1, 1, 0, 0],
                    [1, 1, 0, 0],
                ],
                dtype=np.uint8,
            )
            np.testing.assert_array_equal(binary, expected)

            self.assertEqual(module.area_from_mask(binary), 8)
            self.assertEqual(module.bbox_from_mask(binary), [0, 0, 4, 4])
            self.assertIsInstance(module.mask_to_rle(binary)["counts"], str)

    def test_build_openimages_seg_records_filters_shoe_rows_and_skips_invalid(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "openimages_seg"

            train_root = dataset_dir / "open-images-v7/train"
            validation_root = dataset_dir / "open-images-v7/validation"

            self._write_jpg(train_root / "data/img_keep.jpg", width=6, height=4)
            self._write_jpg(validation_root / "data/img_val.jpg", width=5, height=5)

            self._write_gray_png(
                train_root / "labels/masks/A/mask_keep.png",
                np.array([[255, 0, 0], [255, 255, 0]], dtype=np.uint8),
            )
            self._write_gray_png(
                train_root / "labels/masks/c/mask_empty.png",
                np.zeros((2, 2), dtype=np.uint8),
            )
            self._write_gray_png(
                validation_root / "labels/masks/f/mask_val.png",
                np.array([[0, 255], [255, 255]], dtype=np.uint8),
            )

            self._write_openimages_segmentations_csv(
                train_root / "labels/segmentations.csv",
                [
                    {"ImageID": "img_keep", "LabelName": "/m/01b638", "MaskPath": "a/mask_keep.png"},
                    {"ImageID": "img_keep", "LabelName": "/m/not_shoe", "MaskPath": "a/mask_keep.png"},
                    {"ImageID": "missing_img", "LabelName": "/m/06k2mb", "MaskPath": "a/mask_keep.png"},
                    {"ImageID": "img_keep", "LabelName": "/m/06k2mb", "MaskPath": "z/missing.png"},
                    {"ImageID": "img_keep", "LabelName": "/m/06k2mb", "MaskPath": "c/mask_empty.png"},
                ],
            )
            self._write_openimages_segmentations_csv(
                validation_root / "labels/segmentations.csv",
                [
                    {"ImageID": "img_val", "LabelName": "/m/06k2mb", "MaskPath": "F/mask_val.png"},
                ],
            )

            images, annotations, next_img, next_ann = module.build_openimages_seg_records(
                dataset_dir=dataset_dir,
                start_image_id=10,
                start_annotation_id=20,
            )

            self.assertEqual(next_img, 12)
            self.assertEqual(next_ann, 22)
            self.assertEqual([image["id"] for image in images], [10, 11])
            self.assertEqual([ann["id"] for ann in annotations], [20, 21])
            self.assertEqual(len(images), 2)
            self.assertEqual(len(annotations), 2)
            self.assertEqual(
                [image["file_name"] for image in images],
                [
                    "openimages_seg/open-images-v7/train/data/img_keep.jpg",
                    "openimages_seg/open-images-v7/validation/data/img_val.jpg",
                ],
            )
            for ann in annotations:
                self.assertIsInstance(ann["segmentation"], dict)
                self.assertIsInstance(ann["segmentation"]["counts"], str)

    def test_build_openimages_seg_records_reuses_image_for_multi_mask_rows(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "openimages_seg"
            train_root = dataset_dir / "open-images-v7/train"
            validation_root = dataset_dir / "open-images-v7/validation"
            validation_root.mkdir(parents=True, exist_ok=True)

            self._write_jpg(train_root / "data/shared.jpg", width=4, height=4)
            self._write_gray_png(
                train_root / "labels/masks/1/mask_one.png",
                np.array([[255, 0], [0, 0]], dtype=np.uint8),
            )
            self._write_gray_png(
                train_root / "labels/masks/2/mask_two.png",
                np.array([[0, 0], [0, 255]], dtype=np.uint8),
            )
            self._write_openimages_segmentations_csv(
                train_root / "labels/segmentations.csv",
                [
                    {"ImageID": "shared", "LabelName": "/m/01b638", "MaskPath": "1/mask_one.png"},
                    {"ImageID": "shared", "LabelName": "/m/06k2mb", "MaskPath": "2/mask_two.png"},
                ],
            )
            self._write_openimages_segmentations_csv(
                validation_root / "labels/segmentations.csv",
                [],
            )

            images, annotations, next_img, next_ann = module.build_openimages_seg_records(
                dataset_dir=dataset_dir,
                start_image_id=7,
                start_annotation_id=50,
            )

            self.assertEqual(len(images), 1)
            self.assertEqual(images[0]["id"], 7)
            self.assertEqual(len(annotations), 2)
            self.assertEqual([ann["id"] for ann in annotations], [50, 51])
            self.assertTrue(all(ann["image_id"] == 7 for ann in annotations))
            self.assertTrue(all(isinstance(ann["segmentation"], dict) for ann in annotations))
            self.assertEqual(next_img, 8)
            self.assertEqual(next_ann, 52)

    def test_openimages_adapter_write_coco_round_trip_keeps_relative_unique_images(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "openimages_seg"
            train_root = dataset_dir / "open-images-v7/train"
            validation_root = dataset_dir / "open-images-v7/validation"
            validation_root.mkdir(parents=True, exist_ok=True)

            self._write_jpg(train_root / "data/roundtrip.jpg", width=4, height=4)
            self._write_gray_png(
                train_root / "labels/masks/a/roundtrip_mask.png",
                np.array([[255, 0], [0, 255]], dtype=np.uint8),
            )
            self._write_openimages_segmentations_csv(
                train_root / "labels/segmentations.csv",
                [
                    {"ImageID": "roundtrip", "LabelName": "/m/01b638", "MaskPath": "a/roundtrip_mask.png"},
                    {"ImageID": "roundtrip", "LabelName": "/m/06k2mb", "MaskPath": "a/roundtrip_mask.png"},
                ],
            )
            self._write_openimages_segmentations_csv(
                validation_root / "labels/segmentations.csv",
                [],
            )

            images, annotations, _, _ = module.build_openimages_seg_records(
                dataset_dir=dataset_dir,
                start_image_id=1,
                start_annotation_id=1,
            )

            output_path = Path(tmp_dir) / "openimages_seg.json"
            module.write_coco_json(images, annotations, output_path)
            payload = json.loads(output_path.read_text(encoding="utf-8"))

            self.assertEqual(payload["categories"], [module.SHOE_CATEGORY])
            self.assertEqual(len(payload["images"]), 1)
            self.assertEqual(len(payload["annotations"]), 2)
            for image in payload["images"]:
                self.assertFalse(Path(image["file_name"]).is_absolute())
                self.assertFalse(image["file_name"].startswith("data/shoe_seg/raw/"))

    def test_build_stage_4_outputs_dispatches_openimages_json_through_shared_writer(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            (raw_dir / "openimages_seg").mkdir(parents=True, exist_ok=True)
            unified_dir.mkdir(parents=True, exist_ok=True)

            fake_image = module.make_image(
                1,
                "openimages_seg/open-images-v7/train/data/img.jpg",
                10,
                10,
            )
            fake_annotation = module.make_annotation(
                1,
                1,
                module.mask_to_rle(np.array([[1]], dtype=np.uint8)),
                [0, 0, 1, 1],
                1,
            )

            def _fake_adapter(
                _dataset_dir: Path, start_image_id: int, start_annotation_id: int
            ):
                return [fake_image], [fake_annotation], start_image_id + 1, start_annotation_id + 1

            with patch.object(
                module,
                "STAGE_4_ADAPTERS",
                {"openimages_seg": _fake_adapter},
            ), patch.object(module, "write_coco_json") as write_mock:
                module.build_stage_4_outputs(raw_dir=raw_dir, unified_dir=unified_dir)

            self.assertEqual(write_mock.call_count, 1)
            self.assertEqual(write_mock.call_args.args[2], unified_dir / "openimages_seg.json")

    def test_main_non_check_runs_stage_2_3_and_4_adapters(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            self._create_dataset_roots(
                raw_dir,
                [
                    "kaggle_shoe_seg",
                    "kaggle_people_clothing",
                    "ccp",
                    "modanet",
                    "imaterialist",
                    "openimages_seg",
                ],
            )
            unified_dir.mkdir(parents=True, exist_ok=True)

            fake_image = module.make_image(1, "kaggle_shoe_seg/example.jpg", 10, 10)
            fake_annotation = module.make_annotation(
                1,
                1,
                [[1, 1, 3, 1, 3, 3]],
                [1, 1, 2, 2],
                4,
            )

            def _fake_adapter(
                _dataset_dir: Path, start_image_id: int, start_annotation_id: int
            ):
                return [fake_image], [fake_annotation], start_image_id + 1, start_annotation_id + 1

            with patch.object(module, "RAW_DIR", raw_dir), patch.object(
                module, "UNIFIED_DIR", unified_dir
            ), patch.object(
                module,
                "STAGE_2_ADAPTERS",
                {
                    "kaggle_shoe_seg": _fake_adapter,
                    "kaggle_people_clothing": _fake_adapter,
                    "ccp": _fake_adapter,
                },
            ), patch.object(
                module,
                "STAGE_3_ADAPTERS",
                {
                    "modanet": _fake_adapter,
                    "imaterialist": _fake_adapter,
                },
            ), patch.object(
                module,
                "STAGE_4_ADAPTERS",
                {"openimages_seg": _fake_adapter},
            ), patch.object(
                module,
                "STAGE_5_ADAPTERS",
                {},
            ), patch.object(module, "write_coco_json") as write_mock, patch.object(
                module, "validate_per_dataset_outputs"
            ), patch.object(
                module, "merge_dataset_outputs", return_value=([], [])
            ), patch.object(
                module, "write_split_outputs", return_value={}
            ), patch(
                "sys.argv", ["shoe_seg_normalize_to_coco.py"]
            ):
                exit_code = module.main()

            self.assertEqual(exit_code, 0)
            self.assertEqual(write_mock.call_count, 6)
            written_paths = [call.args[2] for call in write_mock.call_args_list]
            self.assertIn(unified_dir / "openimages_seg.json", written_paths)


if __name__ == "__main__":
    unittest.main()
