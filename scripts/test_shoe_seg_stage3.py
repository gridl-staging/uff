from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from test_shoe_seg_test_support import ShoeSegNormalizeToCocoTestBase


class Stage3StructuredAdapterTests(ShoeSegNormalizeToCocoTestBase):
    """Tests for ModaNet and iMaterialist structured-annotation adapters."""

    # ── ModaNet adapter tests ──

    def test_modanet_adapter_filters_shoe_categories_and_remaps(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "modanet_images"
            ann_path = dataset_dir / "datasets/coco/annotations/instances_all.json"

            source_images = [
                {"id": 10, "file_name": "shoe_img.jpg", "width": 640, "height": 480},
                {"id": 20, "file_name": "hat_only.jpg", "width": 320, "height": 240},
                {"id": 30, "file_name": "boots_img.jpg", "width": 800, "height": 600},
            ]
            source_annotations = [
                {"id": 1, "image_id": 10, "category_id": 4, "segmentation": [[1, 1, 5, 1, 5, 5]], "bbox": [1, 1, 4, 4], "area": 16, "iscrowd": 0},
                {"id": 2, "image_id": 10, "category_id": 2, "segmentation": [[10, 10, 20, 10, 20, 20]], "bbox": [10, 10, 10, 10], "area": 100, "iscrowd": 0},
                {"id": 3, "image_id": 20, "category_id": 1, "segmentation": [[2, 2, 8, 2, 8, 8]], "bbox": [2, 2, 6, 6], "area": 36, "iscrowd": 0},
                {"id": 4, "image_id": 30, "category_id": 3, "segmentation": [[3, 3, 9, 3, 9, 9]], "bbox": [3, 3, 6, 6], "area": 36, "iscrowd": 0},
            ]
            source_categories = [
                {"id": 1, "name": "bag"}, {"id": 2, "name": "belt"},
                {"id": 3, "name": "boots"}, {"id": 4, "name": "footwear"},
            ]
            self._write_modanet_coco_json(ann_path, source_images, source_annotations, source_categories)

            images, annotations, next_img, next_ann = module.build_modanet_records(
                dataset_dir=dataset_dir, start_image_id=1, start_annotation_id=1,
            )

            self.assertEqual(len(annotations), 2)
            self.assertEqual(len(images), 2)

            for ann in annotations:
                self.assertEqual(ann["category_id"], module.SHOE_CATEGORY["id"])

            for img in images:
                self.assertTrue(img["file_name"].startswith("modanet_images/datasets/coco/images/"))
                self.assertFalse(img["file_name"].startswith("/"))

            self.assertEqual([img["id"] for img in images], [1, 2])
            self.assertEqual([ann["id"] for ann in annotations], [1, 2])
            self.assertEqual(next_img, 3)
            self.assertEqual(next_ann, 3)

    def test_modanet_adapter_skips_images_with_no_shoe_annotations(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "modanet_images"
            ann_path = dataset_dir / "datasets/coco/annotations/instances_all.json"

            self._write_modanet_coco_json(
                ann_path,
                [{"id": 1, "file_name": "no_shoes.jpg", "width": 100, "height": 100}],
                [{"id": 1, "image_id": 1, "category_id": 1, "segmentation": [[1, 1, 5, 1, 5, 5]], "bbox": [1, 1, 4, 4], "area": 16, "iscrowd": 0}],
                [{"id": 1, "name": "bag"}],
            )

            images, annotations, _, _ = module.build_modanet_records(
                dataset_dir=dataset_dir, start_image_id=1, start_annotation_id=1,
            )

            self.assertEqual(len(images), 0)
            self.assertEqual(len(annotations), 0)

    def test_modanet_adapter_preserves_segmentation_and_bbox(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "modanet_images"
            ann_path = dataset_dir / "datasets/coco/annotations/instances_all.json"

            original_seg = [[10, 20, 30, 20, 30, 40, 10, 40]]
            original_bbox = [10, 20, 20, 20]
            original_area = 400

            self._write_modanet_coco_json(
                ann_path,
                [{"id": 1, "file_name": "test.jpg", "width": 100, "height": 100}],
                [{"id": 1, "image_id": 1, "category_id": 3, "segmentation": original_seg, "bbox": original_bbox, "area": original_area, "iscrowd": 0}],
                [{"id": 3, "name": "boots"}],
            )

            _, annotations, _, _ = module.build_modanet_records(
                dataset_dir=dataset_dir, start_image_id=1, start_annotation_id=1,
            )

            self.assertEqual(annotations[0]["segmentation"], original_seg)
            self.assertEqual(annotations[0]["bbox"], original_bbox)
            self.assertEqual(annotations[0]["area"], original_area)

    def test_modanet_adapter_writes_valid_coco_json(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "modanet_images"
            ann_path = dataset_dir / "datasets/coco/annotations/instances_all.json"

            self._write_modanet_coco_json(
                ann_path,
                [{"id": 5, "file_name": "shoe.jpg", "width": 200, "height": 150}],
                [{"id": 99, "image_id": 5, "category_id": 4, "segmentation": [[1, 1, 5, 1, 5, 5]], "bbox": [1, 1, 4, 4], "area": 16, "iscrowd": 0}],
                [{"id": 4, "name": "footwear"}],
            )

            images, annotations, _, _ = module.build_modanet_records(
                dataset_dir=dataset_dir, start_image_id=1, start_annotation_id=1,
            )

            output_path = Path(tmp_dir) / "modanet.json"
            module.write_coco_json(images, annotations, output_path)
            payload = json.loads(output_path.read_text(encoding="utf-8"))

            self.assertEqual(payload["categories"], [module.SHOE_CATEGORY])
            self.assertFalse(payload["images"][0]["file_name"].startswith("/"))
            self.assertFalse(payload["images"][0]["file_name"].startswith("data/shoe_seg/raw/"))

    # ── iMaterialist adapter tests ──

    def test_bbox_and_area_from_polygon_uses_shoelace_area(self):
        module = self.module

        polygon = [0.0, 0.0, 4.0, 0.0, 3.0, 2.0, 1.0, 2.0]

        bbox, area = module._bbox_and_area_from_polygon(polygon)

        self.assertEqual(bbox, [0.0, 0.0, 4.0, 2.0])
        self.assertAlmostEqual(area, 6.0)

    def test_imaterialist_adapter_filters_class_23_and_denormalizes_polygons(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "imaterialist"

            self._write_jpg(dataset_dir / "images/train/abc.jpg", width=100, height=200)
            self._write_yolo_label(
                dataset_dir / "labels/train/abc.txt",
                ["23 0.1 0.2 0.5 0.2 0.5 0.8", "5 0.0 0.0 1.0 0.0 1.0 1.0"],
            )

            images, annotations, next_img, next_ann = module.build_imaterialist_records(
                dataset_dir=dataset_dir, start_image_id=1, start_annotation_id=1,
            )

            self.assertEqual(len(images), 1)
            self.assertEqual(len(annotations), 1)
            self.assertEqual(images[0]["file_name"], "imaterialist/images/train/abc.jpg")
            self.assertEqual(images[0]["width"], 100)
            self.assertEqual(images[0]["height"], 200)

            poly = annotations[0]["segmentation"][0]
            self.assertEqual(len(poly), 6)
            self.assertAlmostEqual(poly[0], 0.1 * 100, places=1)
            self.assertAlmostEqual(poly[1], 0.2 * 200, places=1)

            self.assertAlmostEqual(annotations[0]["bbox"][0], 10.0, places=1)
            self.assertAlmostEqual(annotations[0]["bbox"][1], 40.0, places=1)
            self.assertAlmostEqual(annotations[0]["bbox"][2], 40.0, places=1)
            self.assertAlmostEqual(annotations[0]["bbox"][3], 120.0, places=1)

            self.assertEqual(annotations[0]["category_id"], module.SHOE_CATEGORY["id"])
            self.assertEqual(next_img, 2)
            self.assertEqual(next_ann, 2)

    def test_imaterialist_adapter_handles_multiple_splits_and_extensions(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "imaterialist"

            self._write_jpg(dataset_dir / "images/train/img1.jpeg", width=50, height=50)
            self._write_yolo_label(
                dataset_dir / "labels/train/img1.txt",
                ["23 0.2 0.2 0.8 0.2 0.8 0.8"],
            )

            self._write_jpg(dataset_dir / "images/val/img2.png", width=60, height=60)
            self._write_yolo_label(
                dataset_dir / "labels/val/img2.txt",
                ["23 0.1 0.1 0.9 0.1 0.9 0.9"],
            )

            images, annotations, _, _ = module.build_imaterialist_records(
                dataset_dir=dataset_dir, start_image_id=1, start_annotation_id=1,
            )

            self.assertEqual(len(images), 2)
            self.assertEqual(len(annotations), 2)
            file_names = [img["file_name"] for img in images]
            self.assertIn("imaterialist/images/train/img1.jpeg", file_names)
            self.assertIn("imaterialist/images/val/img2.png", file_names)

    def test_imaterialist_adapter_skips_missing_images_and_short_polygons(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "imaterialist"

            self._write_yolo_label(
                dataset_dir / "labels/train/orphan.txt",
                ["23 0.1 0.2 0.5 0.2 0.5 0.8"],
            )

            self._write_jpg(dataset_dir / "images/train/short.jpg", width=50, height=50)
            self._write_yolo_label(
                dataset_dir / "labels/train/short.txt",
                ["23 0.5 0.5"],
            )

            self._write_jpg(dataset_dir / "images/train/noshoe.jpg", width=50, height=50)
            self._write_yolo_label(
                dataset_dir / "labels/train/noshoe.txt",
                ["5 0.1 0.2 0.5 0.2 0.5 0.8"],
            )

            images, annotations, _, _ = module.build_imaterialist_records(
                dataset_dir=dataset_dir, start_image_id=1, start_annotation_id=1,
            )

            self.assertEqual(len(images), 0)
            self.assertEqual(len(annotations), 0)

    def test_imaterialist_adapter_skips_malformed_numeric_nonfinite_and_odd_polygon_lines(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "imaterialist"

            self._write_jpg(dataset_dir / "images/train/mixed.jpg", width=100, height=100)
            self._write_yolo_label(
                dataset_dir / "labels/train/mixed.txt",
                [
                    "23 not-a-number 0.1 0.3 0.1 0.3 0.3",
                    "23 nan 0.1 0.3 0.1 0.3 0.3",
                    "23 inf 0.1 0.3 0.1 0.3 0.3",
                    "23 0.1 0.1 0.3 0.1 0.3 0.3 0.5",
                    "23 0.6 0.6 0.9 0.6 0.9 0.9",
                ],
            )

            images, annotations, next_img, next_ann = module.build_imaterialist_records(
                dataset_dir=dataset_dir, start_image_id=4, start_annotation_id=9,
            )

            self.assertEqual(len(images), 1)
            self.assertEqual(len(annotations), 1)
            self.assertEqual(images[0]["id"], 4)
            self.assertEqual(annotations[0]["id"], 9)
            self.assertEqual(next_img, 5)
            self.assertEqual(next_ann, 10)
            self.assertEqual(
                annotations[0]["segmentation"],
                [[60.0, 60.0, 90.0, 60.0, 90.0, 90.0]],
            )

    def test_imaterialist_adapter_multiple_shoe_annotations_per_image(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "imaterialist"
            self._write_jpg(dataset_dir / "images/train/two_shoes.jpg", width=100, height=100)
            self._write_yolo_label(
                dataset_dir / "labels/train/two_shoes.txt",
                [
                    "23 0.1 0.1 0.3 0.1 0.3 0.3",
                    "23 0.6 0.6 0.9 0.6 0.9 0.9",
                ],
            )

            images, annotations, next_img, next_ann = module.build_imaterialist_records(
                dataset_dir=dataset_dir, start_image_id=1, start_annotation_id=1,
            )

            self.assertEqual(len(images), 1)
            self.assertEqual(len(annotations), 2)
            self.assertEqual(annotations[0]["image_id"], 1)
            self.assertEqual(annotations[1]["image_id"], 1)
            self.assertEqual(next_img, 2)
            self.assertEqual(next_ann, 3)

    def test_imaterialist_adapter_writes_valid_coco_json(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "imaterialist"
            self._write_jpg(dataset_dir / "images/train/shoe.jpg", width=100, height=100)
            self._write_yolo_label(
                dataset_dir / "labels/train/shoe.txt",
                ["23 0.1 0.1 0.5 0.1 0.5 0.5"],
            )

            images, annotations, _, _ = module.build_imaterialist_records(
                dataset_dir=dataset_dir, start_image_id=1, start_annotation_id=1,
            )

            output_path = Path(tmp_dir) / "imaterialist.json"
            module.write_coco_json(images, annotations, output_path)
            payload = json.loads(output_path.read_text(encoding="utf-8"))

            self.assertEqual(payload["categories"], [module.SHOE_CATEGORY])
            image_ids = {img["id"] for img in payload["images"]}
            for ann in payload["annotations"]:
                self.assertIn(ann["image_id"], image_ids)
            for img in payload["images"]:
                self.assertFalse(img["file_name"].startswith("/"))
                self.assertFalse(img["file_name"].startswith("data/shoe_seg/raw/"))

    # ── Stage 3 orchestration and regression tests ──

    def test_stage_3_orchestration_dispatches_modanet_and_imaterialist(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            raw_dir.mkdir(parents=True, exist_ok=True)
            unified_dir.mkdir(parents=True, exist_ok=True)

            for name in ["modanet_images", "imaterialist"]:
                (raw_dir / name).mkdir(parents=True, exist_ok=True)

            image = module.make_image(1, "modanet_images/datasets/coco/images/x.jpg", 10, 10)
            annotation = module.make_annotation(1, 1, [[1, 1, 3, 1, 3, 3]], [1, 1, 2, 2], 4)

            def _fake_adapter(_dataset_dir: Path, start_image_id: int, start_annotation_id: int):
                return [image], [annotation], start_image_id + 1, start_annotation_id + 1

            with patch.object(
                module, "STAGE_3_ADAPTERS",
                {"modanet": _fake_adapter, "imaterialist": _fake_adapter},
            ), patch.object(module, "write_coco_json") as write_mock:
                module.build_stage_3_outputs(raw_dir=raw_dir, unified_dir=unified_dir)

            self.assertEqual(write_mock.call_count, 2)
            written_paths = [call.args[2] for call in write_mock.call_args_list]
            self.assertEqual(written_paths, [
                unified_dir / "modanet.json",
                unified_dir / "imaterialist.json",
            ])

    def test_main_non_check_runs_stage_2_and_3(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            self._create_dataset_roots(raw_dir, list(module.STAGE_2_ADAPTERS) + ["modanet", "imaterialist"])
            unified_dir.mkdir(parents=True, exist_ok=True)

            image = module.make_image(1, "kaggle_shoe_seg/example.jpg", 10, 10)
            annotation = module.make_annotation(1, 1, [[1, 1, 3, 1, 3, 3]], [1, 1, 2, 2], 4)

            def _fake_adapter(_dataset_dir: Path, start_image_id: int, start_annotation_id: int):
                return [image], [annotation], start_image_id + 1, start_annotation_id + 1

            with patch.object(module, "RAW_DIR", raw_dir), patch.object(
                module, "UNIFIED_DIR", unified_dir
            ), patch.object(module, "STAGE_2_ADAPTERS", {
                "kaggle_shoe_seg": _fake_adapter,
                "kaggle_people_clothing": _fake_adapter,
                "ccp": _fake_adapter,
            }), patch.object(module, "STAGE_3_ADAPTERS", {
                "modanet": _fake_adapter,
                "imaterialist": _fake_adapter,
            }), patch.object(module, "STAGE_4_ADAPTERS", {}), patch.object(
                module, "STAGE_5_ADAPTERS", {}
            ), patch.object(
                module, "write_coco_json"
            ) as write_mock, patch.object(
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
            self.assertEqual(write_mock.call_count, 5)
            written_paths = [call.args[2] for call in write_mock.call_args_list]
            self.assertIn(unified_dir / "modanet.json", written_paths)
            self.assertIn(unified_dir / "imaterialist.json", written_paths)

    def test_stage_3_regression_ids_and_relative_paths(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            self._create_dataset_roots(raw_dir)

            modanet_dir = raw_dir / "modanet_images"
            ann_path = modanet_dir / "datasets/coco/annotations/instances_all.json"
            self._write_modanet_coco_json(
                ann_path,
                [{"id": 5, "file_name": "img.jpg", "width": 100, "height": 100}],
                [{"id": 9, "image_id": 5, "category_id": 3, "segmentation": [[1, 1, 5, 1, 5, 5]], "bbox": [1, 1, 4, 4], "area": 16, "iscrowd": 0}],
                [{"id": 3, "name": "boots"}],
            )

            imat_dir = raw_dir / "imaterialist"
            self._write_jpg(imat_dir / "images/train/shoe.jpg", width=100, height=100)
            self._write_yolo_label(
                imat_dir / "labels/train/shoe.txt",
                ["23 0.1 0.1 0.5 0.1 0.5 0.5"],
            )

            module.build_stage_3_outputs(raw_dir=raw_dir, unified_dir=unified_dir)

            for dataset_name in ["modanet", "imaterialist"]:
                payload = json.loads(
                    (unified_dir / f"{dataset_name}.json").read_text(encoding="utf-8")
                )
                image_ids = [img["id"] for img in payload["images"]]
                annotation_ids = [ann["id"] for ann in payload["annotations"]]

                self.assertEqual(image_ids, sorted(image_ids))
                self.assertEqual(annotation_ids, sorted(annotation_ids))
                if image_ids:
                    self.assertEqual(image_ids[0], 1)

                for img in payload["images"]:
                    self.assertFalse(Path(img["file_name"]).is_absolute())
                    self.assertFalse(img["file_name"].startswith("data/shoe_seg/raw/"))
                for ann in payload["annotations"]:
                    self.assertEqual(ann["category_id"], module.SHOE_CATEGORY["id"])


if __name__ == "__main__":
    unittest.main()
