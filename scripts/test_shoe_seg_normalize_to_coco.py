from __future__ import annotations

import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
import json
from pathlib import Path
from unittest.mock import patch

import numpy as np

from test_shoe_seg_test_support import SCRIPT_PATH, ShoeSegNormalizeToCocoTestBase


class ShoeSegNormalizeToCocoTests(ShoeSegNormalizeToCocoTestBase):
    def test_smoke_import_and_manifest_constants(self):
        module = self.module

        self.assertEqual(len(module.DATASETS), 7)
        self.assertEqual(
            {entry["name"]: entry["raw_subdir"] for entry in module.DATASETS},
            {
                "kaggle_shoe_seg": "kaggle_shoe_seg",
                "kaggle_people_clothing": "kaggle_people_clothing",
                "openimages_seg": "openimages_seg",
                "modanet": "modanet_images",
                "imaterialist": "imaterialist",
                "ccp": "ccp",
                "atr": "atr",
            },
        )

        self.assertEqual(len(module.SKIPPED_DATASETS), 2)
        skipped_by_name = {
            entry["name"]: entry["reason"] for entry in module.SKIPPED_DATASETS
        }
        self.assertIn("fashionpedia", skipped_by_name)
        self.assertIn("deepfashion_masks", skipped_by_name)
        self.assertIn("no segmentation masks", skipped_by_name["fashionpedia"].lower())
        self.assertIn("no shoe categories", skipped_by_name["deepfashion_masks"].lower())

        expected_repo_root = SCRIPT_PATH.resolve().parents[1]
        self.assertEqual(module.REPO_ROOT, expected_repo_root)
        self.assertEqual(module.RAW_DIR, expected_repo_root / "data/shoe_seg/raw")
        self.assertEqual(module.UNIFIED_DIR, expected_repo_root / "data/shoe_seg/unified")
        self.assertTrue(module.UNIFIED_DIR.exists())

    def test_mask_helpers_with_known_rectangle(self):
        module = self.module

        binary = np.zeros((100, 100), dtype=np.uint8)
        binary[15:45, 10:30] = 1  # x=10, y=15, width=20, height=30

        polygons = module.mask_to_polygons(binary)
        self.assertGreaterEqual(len(polygons), 1)
        self.assertTrue(any(len(poly) >= 6 for poly in polygons))

        bbox = module.bbox_from_mask(binary)
        self.assertEqual(bbox, [10, 15, 20, 30])

        area = module.area_from_mask(binary)
        self.assertEqual(area, 600)

    def test_mask_to_rle_returns_coco_rle(self):
        module = self.module

        binary = np.zeros((10, 12), dtype=np.uint8)
        binary[2:5, 3:7] = 1

        rle = module.mask_to_rle(binary)
        self.assertIsInstance(rle, dict)
        self.assertEqual(rle["size"], [10, 12])
        self.assertIsInstance(rle["counts"], str)

    def test_make_image_and_annotation(self):
        module = self.module

        image = module.make_image(
            id=3,
            file_name="kaggle_shoe_seg/shoes_dataset/train/images/example.jpg",
            width=640,
            height=480,
        )
        annotation = module.make_annotation(
            id=9,
            image_id=3,
            segmentation=[[10, 10, 20, 10, 20, 20]],
            bbox=[10, 10, 10, 10],
            area=100,
        )

        self.assertEqual(image["id"], 3)
        self.assertEqual(annotation["category_id"], 1)
        self.assertEqual(annotation["iscrowd"], 0)

    def test_write_coco_json_writes_expected_schema(self):
        module = self.module

        images = [
            module.make_image(1, "kaggle_shoe_seg/a.jpg", 100, 100),
            module.make_image(2, "kaggle_people_clothing/b.jpg", 120, 110),
        ]
        annotations = [
            module.make_annotation(1, 1, [[0, 0, 4, 0, 4, 4]], [0, 0, 4, 4], 16),
            module.make_annotation(2, 1, [[5, 5, 9, 5, 9, 9]], [5, 5, 4, 4], 16),
            module.make_annotation(3, 2, [[1, 1, 3, 1, 3, 3]], [1, 1, 2, 2], 4),
        ]

        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "synthetic.json"
            module.write_coco_json(images, annotations, output_path)

            written = json.loads(output_path.read_text())

        self.assertEqual(written["categories"], [{"id": 1, "name": "shoe"}])
        self.assertEqual(len(written["images"]), 2)
        self.assertEqual(len(written["annotations"]), 3)
        image_ids = {image["id"] for image in written["images"]}
        self.assertTrue(all(ann["image_id"] in image_ids for ann in written["annotations"]))
        self.assertTrue(all(not image["file_name"].startswith("/") for image in written["images"]))

    def test_write_coco_json_rejects_non_relative_file_names(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "invalid.json"

            with self.assertRaises(ValueError):
                module.write_coco_json(
                    images=[module.make_image(1, "/abs/path.jpg", 10, 10)],
                    annotations=[],
                    output_path=output_path,
                )

            with self.assertRaises(ValueError):
                module.write_coco_json(
                    images=[
                        module.make_image(
                            1, "data/shoe_seg/raw/kaggle_shoe_seg/path.jpg", 10, 10
                        )
                    ],
                    annotations=[],
                    output_path=output_path,
                )

            with self.assertRaises(ValueError):
                module.write_coco_json(
                    images=[module.make_image(1, "../outside.jpg", 10, 10)],
                    annotations=[],
                    output_path=output_path,
                )

    def test_write_coco_json_rejects_missing_image_ids(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "orphan-annotation.json"

            with self.assertRaises(ValueError) as context:
                module.write_coco_json(
                    images=[module.make_image(1, "kaggle_shoe_seg/a.jpg", 10, 10)],
                    annotations=[
                        module.make_annotation(
                            1,
                            99,
                            [[0, 0, 4, 0, 4, 4]],
                            [0, 0, 4, 4],
                            16,
                        )
                    ],
                    output_path=output_path,
                )

        self.assertIn("missing image_id values", str(context.exception))
        self.assertIn("99", str(context.exception))

    def test_check_inputs_rejects_non_directory_dataset_paths(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir)
            bad_dataset = module.DATASETS[0]

            for dataset in module.DATASETS[1:]:
                (raw_dir / dataset["raw_subdir"]).mkdir(parents=True, exist_ok=True)

            invalid_path = raw_dir / bad_dataset["raw_subdir"]
            invalid_path.parent.mkdir(parents=True, exist_ok=True)
            invalid_path.write_text("not a directory", encoding="utf-8")

            with patch.object(module, "RAW_DIR", raw_dir):
                stdout = StringIO()
                with redirect_stdout(stdout):
                    with self.assertRaises(FileNotFoundError) as context:
                        module.check_inputs()

        self.assertIn(bad_dataset["name"], str(context.exception))
        self.assertIn("(expected directory)", str(context.exception))
        self.assertIn("Skipping fashionpedia", stdout.getvalue())

    def test_build_stage_2_outputs_dispatches_adapters_to_dataset_json_paths(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            raw_dir.mkdir(parents=True, exist_ok=True)
            unified_dir.mkdir(parents=True, exist_ok=True)

            for dataset_name in [
                "kaggle_shoe_seg",
                "kaggle_people_clothing",
                "ccp",
            ]:
                (raw_dir / dataset_name).mkdir(parents=True, exist_ok=True)

            image = module.make_image(1, "kaggle_shoe_seg/example.jpg", 10, 10)
            annotation = module.make_annotation(
                1, 1, [[1, 1, 3, 1, 3, 3]], [1, 1, 2, 2], 4
            )

            def _fake_adapter(_dataset_dir: Path, start_image_id: int, start_annotation_id: int):
                return [image], [annotation], start_image_id + 1, start_annotation_id + 1

            with patch.object(
                module,
                "STAGE_2_ADAPTERS",
                {
                    "kaggle_shoe_seg": _fake_adapter,
                    "kaggle_people_clothing": _fake_adapter,
                    "ccp": _fake_adapter,
                },
            ), patch.object(module, "write_coco_json") as write_mock:
                module.build_stage_2_outputs(raw_dir=raw_dir, unified_dir=unified_dir)

            self.assertEqual(write_mock.call_count, 3)
            written = [call.args[2] for call in write_mock.call_args_list]
            self.assertEqual(
                written,
                [
                    unified_dir / "kaggle_shoe_seg.json",
                    unified_dir / "kaggle_people_clothing.json",
                    unified_dir / "ccp.json",
                ],
            )

    def test_main_check_only_does_not_write_outputs(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            self._create_dataset_roots(raw_dir)
            unified_dir.mkdir(parents=True, exist_ok=True)

            with patch.object(module, "RAW_DIR", raw_dir), patch.object(
                module, "UNIFIED_DIR", unified_dir
            ), patch.object(module, "build_stage_2_outputs") as build2_mock, patch.object(
                module, "build_stage_3_outputs"
            ) as build3_mock, patch(
                "sys.argv", ["shoe_seg_normalize_to_coco.py", "--check"]
            ):
                exit_code = module.main()

            self.assertEqual(exit_code, 0)
            build2_mock.assert_not_called()
            build3_mock.assert_not_called()
            self.assertEqual(list(unified_dir.glob("*.json")), [])

    def test_kaggle_shoe_seg_adapter_extracts_green_masks_and_relative_paths(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "kaggle_shoe_seg"
            train_images_dir = dataset_dir / "shoes_dataset/train/images"
            train_masks_dir = dataset_dir / "shoes_dataset/train/masks"
            valid_images_dir = dataset_dir / "shoes_dataset/valid/images"
            valid_masks_dir = dataset_dir / "shoes_dataset/valid/masks"
            train_images_dir.mkdir(parents=True, exist_ok=True)
            train_masks_dir.mkdir(parents=True, exist_ok=True)
            valid_images_dir.mkdir(parents=True, exist_ok=True)
            valid_masks_dir.mkdir(parents=True, exist_ok=True)

            self._write_jpg(train_images_dir / "shoe_a.jpg", width=8, height=6)
            self._write_jpg(train_images_dir / "shoe_empty.jpg", width=8, height=6)
            self._write_jpg(valid_images_dir / "shoe_missing_mask.jpg", width=8, height=6)

            shoe_mask = np.zeros((6, 8, 3), dtype=np.uint8)
            shoe_mask[2:5, 1:4] = np.array([44, 153, 80], dtype=np.uint8)
            self._write_rgb_png(train_masks_dir / "shoe_a.png", shoe_mask)

            empty_mask = np.zeros((6, 8, 3), dtype=np.uint8)
            self._write_rgb_png(train_masks_dir / "shoe_empty.png", empty_mask)

            images, annotations, next_image_id, next_annotation_id = (
                module.build_kaggle_shoe_seg_records(
                    dataset_dir=dataset_dir,
                    start_image_id=1,
                    start_annotation_id=1,
                )
            )

            self.assertEqual(len(images), 1)
            self.assertEqual(len(annotations), 1)
            self.assertEqual(next_image_id, 2)
            self.assertEqual(next_annotation_id, 2)
            self.assertEqual(
                images[0]["file_name"],
                "kaggle_shoe_seg/shoes_dataset/train/images/shoe_a.jpg",
            )

            expected_binary = np.zeros((6, 8), dtype=np.uint8)
            expected_binary[2:5, 1:4] = 1
            self.assertEqual(
                annotations[0]["bbox"], module.bbox_from_mask(expected_binary)
            )
            self.assertEqual(
                annotations[0]["area"], module.area_from_mask(expected_binary)
            )

    def test_kaggle_shoe_seg_adapter_records_write_with_shared_schema(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "kaggle_shoe_seg"
            train_images_dir = dataset_dir / "shoes_dataset/train/images"
            train_masks_dir = dataset_dir / "shoes_dataset/train/masks"
            train_images_dir.mkdir(parents=True, exist_ok=True)
            train_masks_dir.mkdir(parents=True, exist_ok=True)

            self._write_jpg(train_images_dir / "shoe_a.jpg", width=8, height=6)
            shoe_mask = np.zeros((6, 8, 3), dtype=np.uint8)
            shoe_mask[1:4, 2:6] = np.array([44, 153, 80], dtype=np.uint8)
            self._write_rgb_png(train_masks_dir / "shoe_a.png", shoe_mask)

            images, annotations, _, _ = module.build_kaggle_shoe_seg_records(
                dataset_dir=dataset_dir,
                start_image_id=1,
                start_annotation_id=1,
            )

            output_path = Path(tmp_dir) / "kaggle_shoe_seg.json"
            module.write_coco_json(images, annotations, output_path)
            payload = json.loads(output_path.read_text(encoding="utf-8"))

            self.assertEqual(payload["categories"], [module.SHOE_CATEGORY])
            self.assertEqual(payload["images"][0]["file_name"], images[0]["file_name"])
            self.assertFalse(payload["images"][0]["file_name"].startswith("/"))

    def test_kaggle_people_clothing_adapter_handles_lookup_extensions_and_class_39(
        self,
    ):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "kaggle_people_clothing"
            images_dir = dataset_dir / "jpeg_images/IMAGES"
            masks_dir = dataset_dir / "png_masks/MASKS"
            images_dir.mkdir(parents=True, exist_ok=True)
            masks_dir.mkdir(parents=True, exist_ok=True)

            self._write_jpg(images_dir / "img_0001.jpeg", width=12, height=9)
            self._write_jpg(images_dir / "img_0004.JPG", width=12, height=9)

            mask_1 = np.zeros((9, 12), dtype=np.uint8)
            mask_1[2:6, 3:8] = 39
            self._write_gray_png(masks_dir / "seg_0001.png", mask_1)

            mask_2 = np.zeros((9, 12), dtype=np.uint8)
            self._write_gray_png(masks_dir / "seg_0002.png", mask_2)

            mask_3 = np.zeros((9, 12), dtype=np.uint8)
            mask_3[1:3, 1:3] = 39
            self._write_gray_png(masks_dir / "seg_0003.png", mask_3)

            mask_4 = np.zeros((9, 12), dtype=np.uint8)
            mask_4[4:8, 2:6] = 39
            self._write_gray_png(masks_dir / "seg_0004.png", mask_4)

            images, annotations, next_image_id, next_annotation_id = (
                module.build_kaggle_people_clothing_records(
                    dataset_dir=dataset_dir,
                    start_image_id=5,
                    start_annotation_id=9,
                )
            )

            self.assertEqual(len(images), 2)
            self.assertEqual(len(annotations), 2)
            self.assertEqual(next_image_id, 7)
            self.assertEqual(next_annotation_id, 11)
            self.assertEqual(
                [image["file_name"] for image in images],
                [
                    "kaggle_people_clothing/jpeg_images/IMAGES/img_0001.jpeg",
                    "kaggle_people_clothing/jpeg_images/IMAGES/img_0004.JPG",
                ],
            )
            self.assertEqual([ann["id"] for ann in annotations], [9, 10])
            self.assertTrue(all(ann["category_id"] == module.SHOE_CATEGORY["id"] for ann in annotations))

    def test_kaggle_people_clothing_records_write_from_shared_helpers(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "kaggle_people_clothing"
            images_dir = dataset_dir / "jpeg_images/IMAGES"
            masks_dir = dataset_dir / "png_masks/MASKS"
            images_dir.mkdir(parents=True, exist_ok=True)
            masks_dir.mkdir(parents=True, exist_ok=True)

            self._write_jpg(images_dir / "img_1234.png", width=12, height=9)
            mask = np.zeros((9, 12), dtype=np.uint8)
            mask[2:5, 2:7] = 39
            self._write_gray_png(masks_dir / "seg_1234.png", mask)

            images, annotations, _, _ = module.build_kaggle_people_clothing_records(
                dataset_dir=dataset_dir,
                start_image_id=1,
                start_annotation_id=1,
            )
            output_path = Path(tmp_dir) / "kaggle_people_clothing.json"
            module.write_coco_json(images, annotations, output_path)
            payload = json.loads(output_path.read_text(encoding="utf-8"))

            self.assertEqual([image["id"] for image in payload["images"]], [1])
            self.assertEqual([annotation["id"] for annotation in payload["annotations"]], [1])
            self.assertEqual(
                [annotation["category_id"] for annotation in payload["annotations"]],
                [module.SHOE_CATEGORY["id"]],
            )

    def test_ccp_adapter_merges_all_footwear_colors_and_skips_non_footwear(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "ccp"
            images_dir = dataset_dir / "images"
            masks_dir = dataset_dir / "labels/pixel_level_labels_colored"
            images_dir.mkdir(parents=True, exist_ok=True)
            masks_dir.mkdir(parents=True, exist_ok=True)

            self._write_jpg(images_dir / "look_1.jpg", width=20, height=20)
            self._write_jpg(images_dir / "look_2.jpg", width=20, height=20)

            mask_with_shoes = np.zeros((20, 20, 3), dtype=np.uint8)
            for index, color in enumerate(module.CCP_SHOE_COLORS):
                row = 1 + index
                mask_with_shoes[row : row + 2, 1:3] = np.array(color, dtype=np.uint8)
            mask_with_shoes[15:18, 15:18] = np.array([255, 0, 255], dtype=np.uint8)
            self._write_rgb_png(masks_dir / "look_1.png", mask_with_shoes)

            non_shoe_mask = np.zeros((20, 20, 3), dtype=np.uint8)
            non_shoe_mask[1:4, 1:4] = np.array([255, 0, 255], dtype=np.uint8)
            self._write_rgb_png(masks_dir / "look_2.png", non_shoe_mask)

            missing_image_mask = np.zeros((20, 20, 3), dtype=np.uint8)
            missing_image_mask[1:4, 1:4] = np.array(module.CCP_SHOE_COLORS[0], dtype=np.uint8)
            self._write_rgb_png(masks_dir / "look_3.png", missing_image_mask)

            images, annotations, next_image_id, next_annotation_id = (
                module.build_ccp_records(
                    dataset_dir=dataset_dir,
                    start_image_id=1,
                    start_annotation_id=1,
                )
            )

            self.assertEqual(len(images), 1)
            self.assertEqual(len(annotations), 1)
            self.assertEqual(next_image_id, 2)
            self.assertEqual(next_annotation_id, 2)
            self.assertEqual(images[0]["file_name"], "ccp/images/look_1.jpg")

            expected_binary = np.zeros((20, 20), dtype=np.uint8)
            for index in range(len(module.CCP_SHOE_COLORS)):
                row = 1 + index
                expected_binary[row : row + 2, 1:3] = 1
            self.assertEqual(
                annotations[0]["bbox"], module.bbox_from_mask(expected_binary)
            )
            self.assertEqual(
                annotations[0]["area"], module.area_from_mask(expected_binary)
            )

    def test_stage_2_regression_outputs_have_deterministic_ids_and_relative_paths(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            self._create_dataset_roots(raw_dir)

            kaggle_shoe_seg_dir = raw_dir / "kaggle_shoe_seg"
            self._write_jpg(
                kaggle_shoe_seg_dir / "shoes_dataset/train/images/s1.jpg", width=8, height=6
            )
            mask = np.zeros((6, 8, 3), dtype=np.uint8)
            mask[1:4, 1:5] = np.array([44, 153, 80], dtype=np.uint8)
            self._write_rgb_png(
                kaggle_shoe_seg_dir / "shoes_dataset/train/masks/s1.png",
                mask,
            )

            kaggle_people_dir = raw_dir / "kaggle_people_clothing"
            self._write_jpg(
                kaggle_people_dir / "jpeg_images/IMAGES/img_0001.jpeg", width=10, height=7
            )
            people_mask = np.zeros((7, 10), dtype=np.uint8)
            people_mask[2:5, 2:6] = 39
            self._write_gray_png(
                kaggle_people_dir / "png_masks/MASKS/seg_0001.png",
                people_mask,
            )

            ccp_dir = raw_dir / "ccp"
            self._write_jpg(ccp_dir / "images/look.jpg", width=10, height=7)
            ccp_mask = np.zeros((7, 10, 3), dtype=np.uint8)
            ccp_mask[1:4, 1:5] = np.array(module.CCP_SHOE_COLORS[0], dtype=np.uint8)
            self._write_rgb_png(
                ccp_dir / "labels/pixel_level_labels_colored/look.png",
                ccp_mask,
            )

            module.build_stage_2_outputs(raw_dir=raw_dir, unified_dir=unified_dir)

            for dataset_name in ["kaggle_shoe_seg", "kaggle_people_clothing", "ccp"]:
                payload = json.loads(
                    (unified_dir / f"{dataset_name}.json").read_text(encoding="utf-8")
                )
                image_ids = [image["id"] for image in payload["images"]]
                annotation_ids = [annotation["id"] for annotation in payload["annotations"]]

                self.assertEqual(image_ids, sorted(image_ids))
                self.assertEqual(annotation_ids, sorted(annotation_ids))
                if image_ids:
                    self.assertEqual(image_ids[0], 1)
                if annotation_ids:
                    self.assertEqual(annotation_ids[0], 1)

                for image in payload["images"]:
                    self.assertFalse(Path(image["file_name"]).is_absolute())
                    self.assertFalse(image["file_name"].startswith("data/shoe_seg/raw/"))
                for annotation in payload["annotations"]:
                    self.assertEqual(annotation["category_id"], module.SHOE_CATEGORY["id"])

    def test_main_non_check_only_requires_active_dataset_roots(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            active_names = (
                list(module.STAGE_2_ADAPTERS)
                + list(module.STAGE_3_ADAPTERS)
                + list(module.STAGE_4_ADAPTERS)
                + list(module.STAGE_5_ADAPTERS)
            )
            self._create_dataset_roots(raw_dir, active_names)
            unified_dir.mkdir(parents=True, exist_ok=True)

            image = module.make_image(1, "kaggle_shoe_seg/example.jpg", 10, 10)
            annotation = module.make_annotation(
                1, 1, [[1, 1, 3, 1, 3, 3]], [1, 1, 2, 2], 4
            )

            def _fake_adapter(
                _dataset_dir: Path, start_image_id: int, start_annotation_id: int
            ):
                return [image], [annotation], start_image_id + 1, start_annotation_id + 1

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
                module, "STAGE_3_ADAPTERS",
                {"modanet": _fake_adapter, "imaterialist": _fake_adapter},
            ), patch.object(
                module, "STAGE_4_ADAPTERS",
                {"openimages_seg": _fake_adapter},
            ), patch.object(
                module, "STAGE_5_ADAPTERS",
                {"atr": _fake_adapter},
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
            self.assertEqual(write_mock.call_count, 7)

    def test_stage_3_shared_helper_resolve_relative_file_name(self):
        module = self.module

        file_name = module._structured_relative_file_name(
            "modanet_images", "datasets", "coco", "images", "shoe.jpg"
        )

        self.assertEqual(file_name, "modanet_images/datasets/coco/images/shoe.jpg")
        self.assertFalse(file_name.startswith("/"))
        self.assertFalse(file_name.startswith("data/shoe_seg/raw/"))

    def test_stage_3_shared_helper_remap_structured_annotation(self):
        module = self.module

        annotation = module._remap_structured_annotation(
            annotation_id=7,
            image_id=11,
            segmentation=[[1, 2, 3, 4, 5, 6]],
            bbox=[1.0, 2.0, 4.0, 5.0],
            area=20.5,
            iscrowd=1,
        )

        self.assertEqual(annotation["id"], 7)
        self.assertEqual(annotation["image_id"], 11)
        self.assertEqual(annotation["category_id"], module.SHOE_CATEGORY["id"])
        self.assertEqual(annotation["segmentation"], [[1, 2, 3, 4, 5, 6]])
        self.assertEqual(annotation["bbox"], [1, 2, 4, 5])
        self.assertEqual(annotation["area"], 20)
        self.assertEqual(annotation["iscrowd"], 1)

    def test_build_modanet_records_filters_categories_and_emits_relative_paths(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "modanet_images"
            annotations_path = dataset_dir / "datasets/coco/annotations/instances_all.json"
            self._write_modanet_coco_json(
                annotations_path=annotations_path,
                images=[
                    {"id": 10, "file_name": "shoe.jpg", "width": 320, "height": 240},
                    {"id": 11, "file_name": "hat.jpg", "width": 320, "height": 240},
                ],
                annotations=[
                    {
                        "id": 1,
                        "image_id": 10,
                        "category_id": 4,
                        "segmentation": [[1, 1, 5, 1, 5, 5]],
                        "bbox": [1, 1, 4, 4],
                        "area": 16,
                    },
                    {
                        "id": 2,
                        "image_id": 11,
                        "category_id": 1,
                        "segmentation": [[2, 2, 8, 2, 8, 8]],
                        "bbox": [2, 2, 6, 6],
                        "area": 36,
                    },
                ],
                categories=[
                    {"id": 1, "name": "bag"},
                    {"id": 4, "name": "footwear"},
                ],
            )

            images, annotations, _, _ = module.build_modanet_records(
                dataset_dir=dataset_dir,
                start_image_id=1,
                start_annotation_id=1,
            )

            self.assertEqual([image["file_name"] for image in images], [
                "modanet_images/datasets/coco/images/shoe.jpg"
            ])
            self.assertEqual(len(annotations), 1)
            self.assertEqual(annotations[0]["category_id"], module.SHOE_CATEGORY["id"])
            self.assertEqual(annotations[0]["segmentation"], [[1, 1, 5, 1, 5, 5]])
            self.assertEqual(annotations[0]["bbox"], [1, 1, 4, 4])

    def test_build_imaterialist_records_uses_shared_lookup_polygon_and_relative_paths(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "imaterialist"
            self._write_jpg(dataset_dir / "images/train/look.jpg", width=100, height=200)
            self._write_yolo_label(
                dataset_dir / "labels/train/look.txt",
                [
                    "23 0.1 0.2 0.5 0.2 0.5 0.8",
                    "5 0.0 0.0 1.0 0.0 1.0 1.0",
                ],
            )
            self._write_yolo_label(
                dataset_dir / "labels/train/orphan.txt",
                ["23 0.2 0.2 0.4 0.2 0.4 0.4"],
            )

            images, annotations, _, _ = module.build_imaterialist_records(
                dataset_dir=dataset_dir,
                start_image_id=1,
                start_annotation_id=1,
            )

            self.assertEqual(len(images), 1)
            self.assertEqual(images[0]["file_name"], "imaterialist/images/train/look.jpg")
            self.assertEqual(len(annotations), 1)
            self.assertEqual(annotations[0]["category_id"], module.SHOE_CATEGORY["id"])
            self.assertEqual(annotations[0]["bbox"], [10, 40, 40, 120])

    def test_stage_3_orchestration_writes_modanet_and_imaterialist_json(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            raw_dir.mkdir(parents=True, exist_ok=True)
            unified_dir.mkdir(parents=True, exist_ok=True)
            (raw_dir / "modanet_images").mkdir(parents=True, exist_ok=True)
            (raw_dir / "imaterialist").mkdir(parents=True, exist_ok=True)

            fake_image = module.make_image(1, "modanet_images/datasets/coco/images/x.jpg", 10, 10)
            fake_annotation = module.make_annotation(
                1, 1, [[1, 1, 3, 1, 3, 3]], [1, 1, 2, 2], 4
            )

            def _fake_adapter(
                _dataset_dir: Path, start_image_id: int, start_annotation_id: int
            ):
                return [fake_image], [fake_annotation], start_image_id + 1, start_annotation_id + 1

            with patch.object(
                module,
                "STAGE_3_ADAPTERS",
                {"modanet": _fake_adapter, "imaterialist": _fake_adapter},
            ), patch.object(module, "write_coco_json") as write_mock:
                module.build_stage_3_outputs(raw_dir=raw_dir, unified_dir=unified_dir)

            self.assertEqual(write_mock.call_count, 2)
            self.assertEqual(
                [call.args[2] for call in write_mock.call_args_list],
                [unified_dir / "modanet.json", unified_dir / "imaterialist.json"],
            )

def load_tests(loader, standard_tests, _pattern):
    stage3_module = __import__("test_shoe_seg_stage3")
    stage4_module = __import__("test_shoe_seg_stage4")
    stage5_module = __import__("test_shoe_seg_stage5")
    stage6_module = __import__("test_shoe_seg_stage6")
    standard_tests.addTests(loader.loadTestsFromModule(stage3_module))
    standard_tests.addTests(loader.loadTestsFromModule(stage4_module))
    standard_tests.addTests(loader.loadTestsFromModule(stage5_module))
    standard_tests.addTests(loader.loadTestsFromModule(stage6_module))
    return standard_tests


if __name__ == "__main__":
    unittest.main()
