from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from test_shoe_seg_test_support import ShoeSegNormalizeToCocoTestBase


class Stage6FinalizeWorkflowTests(ShoeSegNormalizeToCocoTestBase):
    """Tests for Stage 6 output validation, merge/split generation, and orchestration."""

    def _dataset_prefix(self, dataset_name: str) -> str:
        return self.module.DATASET_RAW_SUBDIR_BY_NAME[dataset_name]

    def _write_valid_dataset_output(
        self,
        *,
        unified_dir: Path,
        dataset_name: str,
        image_id: int = 1,
        annotation_id: int = 1,
    ) -> None:
        module = self.module
        image = module.make_image(
            image_id,
            f"{self._dataset_prefix(dataset_name)}/image_{image_id}.jpg",
            10,
            10,
        )
        annotation = module.make_annotation(
            annotation_id,
            image_id,
            [[1, 1, 4, 1, 4, 4]],
            [1, 1, 3, 3],
            9,
        )
        module.write_coco_json(
            images=[image],
            annotations=[annotation],
            output_path=unified_dir / f"{dataset_name}.json",
        )

    def _write_all_valid_dataset_outputs(self, unified_dir: Path) -> None:
        for dataset in self.module.DATASETS:
            self._write_valid_dataset_output(
                unified_dir=unified_dir,
                dataset_name=dataset["name"],
            )

    def test_validate_per_dataset_outputs_requires_manifest_derived_json_set(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            unified_dir = Path(tmp_dir) / "unified"
            unified_dir.mkdir(parents=True, exist_ok=True)
            self._write_all_valid_dataset_outputs(unified_dir)

            missing_dataset_name = module.DATASETS[-1]["name"]
            (unified_dir / f"{missing_dataset_name}.json").unlink()

            with self.assertRaises(FileNotFoundError) as context:
                module.validate_per_dataset_outputs(unified_dir=unified_dir)

        self.assertIn(missing_dataset_name, str(context.exception))

    def test_dataset_output_paths_rejects_parent_escape_dataset_names(self):
        with self.assertRaises(ValueError) as context:
            self.module.shoe_seg_stage6_workflow.dataset_output_paths(
                Path("/tmp/unified"),
                ["../escape"],
            )

        self.assertIn("dataset_name", str(context.exception))
        self.assertIn("../escape", str(context.exception))

    def test_validate_coco_output_rejects_empty_images_or_annotations(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "kaggle_shoe_seg.json"
            self._write_raw_coco_json(
                output_path,
                categories=[module.SHOE_CATEGORY],
                images=[],
                annotations=[],
            )

            with self.assertRaises(ValueError) as context:
                module.validate_coco_output(output_path)

        self.assertIn("must contain at least one image", str(context.exception))

    def test_validate_coco_output_rejects_category_drift(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "kaggle_shoe_seg.json"
            self._write_raw_coco_json(
                output_path,
                categories=[{"id": 77, "name": "sneaker"}],
                images=[{"id": 1, "file_name": "kaggle_shoe_seg/a.jpg", "width": 1, "height": 1}],
                annotations=[
                    {
                        "id": 1,
                        "image_id": 1,
                        "category_id": 77,
                        "segmentation": [[0, 0, 1, 0, 1, 1]],
                        "bbox": [0, 0, 1, 1],
                        "area": 1,
                        "iscrowd": 0,
                    }
                ],
            )

            with self.assertRaises(ValueError) as context:
                module.validate_coco_output(output_path)

        self.assertIn("categories", str(context.exception))

    def test_validate_coco_output_rejects_broken_annotation_image_reference(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "kaggle_shoe_seg.json"
            self._write_raw_coco_json(
                output_path,
                categories=[module.SHOE_CATEGORY],
                images=[{"id": 1, "file_name": "kaggle_shoe_seg/a.jpg", "width": 1, "height": 1}],
                annotations=[
                    {
                        "id": 1,
                        "image_id": 999,
                        "category_id": module.SHOE_CATEGORY["id"],
                        "segmentation": [[0, 0, 1, 0, 1, 1]],
                        "bbox": [0, 0, 1, 1],
                        "area": 1,
                        "iscrowd": 0,
                    }
                ],
            )

            with self.assertRaises(ValueError) as context:
                module.validate_coco_output(output_path)

        self.assertIn("missing image_id", str(context.exception))

    def test_validate_coco_output_rejects_malformed_image_records_with_value_error(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "kaggle_shoe_seg.json"
            self._write_raw_coco_json(
                output_path,
                categories=[module.SHOE_CATEGORY],
                images=[{"file_name": "kaggle_shoe_seg/a.jpg", "width": 1, "height": 1}],
                annotations=[
                    {
                        "id": 1,
                        "image_id": 1,
                        "category_id": module.SHOE_CATEGORY["id"],
                        "segmentation": [[0, 0, 1, 0, 1, 1]],
                        "bbox": [0, 0, 1, 1],
                        "area": 1,
                        "iscrowd": 0,
                    }
                ],
            )

            with self.assertRaises(ValueError) as context:
                module.validate_coco_output(output_path)

        self.assertIn("image", str(context.exception))
        self.assertIn("id", str(context.exception))

    def test_validate_coco_output_rejects_absolute_or_raw_prefixed_file_names(self):
        module = self.module

        invalid_file_names = [
            "/absolute/path.jpg",
            "data/shoe_seg/raw/kaggle_shoe_seg/path.jpg",
        ]

        for invalid_file_name in invalid_file_names:
            with self.subTest(file_name=invalid_file_name):
                with tempfile.TemporaryDirectory() as tmp_dir:
                    output_path = Path(tmp_dir) / "kaggle_shoe_seg.json"
                    self._write_raw_coco_json(
                        output_path,
                        categories=[module.SHOE_CATEGORY],
                        images=[
                            {
                                "id": 1,
                                "file_name": invalid_file_name,
                                "width": 1,
                                "height": 1,
                            }
                        ],
                        annotations=[
                            {
                                "id": 1,
                                "image_id": 1,
                                "category_id": module.SHOE_CATEGORY["id"],
                                "segmentation": [[0, 0, 1, 0, 1, 1]],
                                "bbox": [0, 0, 1, 1],
                                "area": 1,
                                "iscrowd": 0,
                            }
                        ],
                    )

                    with self.assertRaises(ValueError):
                        module.validate_coco_output(output_path)

    def test_merge_dataset_outputs_reads_only_manifest_jsons_and_remaps_ids(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            unified_dir = Path(tmp_dir) / "unified"
            unified_dir.mkdir(parents=True, exist_ok=True)
            self._write_all_valid_dataset_outputs(unified_dir)

            self._write_raw_coco_json(
                unified_dir / "split_train.json",
                categories=[module.SHOE_CATEGORY],
                images=[{"id": 999, "file_name": "split_train/bad.jpg", "width": 1, "height": 1}],
                annotations=[
                    {
                        "id": 999,
                        "image_id": 999,
                        "category_id": module.SHOE_CATEGORY["id"],
                        "segmentation": [[0, 0, 1, 0, 1, 1]],
                        "bbox": [0, 0, 1, 1],
                        "area": 1,
                        "iscrowd": 0,
                    }
                ],
            )

            merged_images, merged_annotations = module.merge_dataset_outputs(unified_dir)

        self.assertEqual(len(merged_images), len(module.DATASETS))
        self.assertEqual(len(merged_annotations), len(module.DATASETS))

        image_ids = [image["id"] for image in merged_images]
        annotation_ids = [annotation["id"] for annotation in merged_annotations]
        self.assertEqual(len(image_ids), len(set(image_ids)))
        self.assertEqual(len(annotation_ids), len(set(annotation_ids)))

        merged_image_id_set = set(image_ids)
        self.assertTrue(all(ann["image_id"] in merged_image_id_set for ann in merged_annotations))

    def test_build_split_membership_is_deterministic_and_complete(self):
        module = self.module

        images = [
            module.make_image(index + 1, f"dataset_{index}/image.jpg", 10, 10)
            for index in range(20)
        ]

        membership_one = module._build_split_membership(images)
        membership_two = module._build_split_membership(images)

        self.assertEqual(membership_one, membership_two)
        all_members = (
            membership_one["train"]
            + membership_one["val"]
            + membership_one["test"]
        )
        self.assertEqual(sorted(all_members), [image["id"] for image in images])

    def test_build_split_membership_uses_manifest_raw_subdir_prefix_order(self):
        module = self.module
        images = [module.make_image(1, "modanet_images/example.jpg", 10, 10)]
        expected_prefix_order = [dataset["raw_subdir"] for dataset in module.DATASETS]

        with patch.object(
            module.shoe_seg_stage6_workflow,
            "build_split_membership",
            return_value={"train": [], "val": [], "test": []},
        ) as build_mock:
            membership = module._build_split_membership(images)

        self.assertEqual(membership, {"train": [], "val": [], "test": []})
        build_mock.assert_called_once_with(images, expected_prefix_order, seed=42)

    def test_write_split_outputs_writes_three_split_jsons_with_valid_references(self):
        module = self.module

        images = [
            module.make_image(1, "kaggle_shoe_seg/a.jpg", 10, 10),
            module.make_image(2, "kaggle_people_clothing/b.jpg", 10, 10),
            module.make_image(3, "openimages_seg/c.jpg", 10, 10),
            module.make_image(4, "modanet_images/d.jpg", 10, 10),
            module.make_image(5, "imaterialist/e.jpg", 10, 10),
            module.make_image(6, "ccp/f.jpg", 10, 10),
            module.make_image(7, "atr/g.jpg", 10, 10),
        ]
        annotations = [
            module.make_annotation(i, i, [[1, 1, 4, 1, 4, 4]], [1, 1, 3, 3], 9)
            for i in range(1, 8)
        ]

        with tempfile.TemporaryDirectory() as tmp_dir:
            unified_dir = Path(tmp_dir) / "unified"
            module.write_split_outputs(
                images=images,
                annotations=annotations,
                unified_dir=unified_dir,
            )

            for split_name in ("train", "val", "test"):
                split_path = unified_dir / f"split_{split_name}.json"
                self.assertTrue(split_path.is_file())
                payload = json.loads(split_path.read_text(encoding="utf-8"))
                image_ids = {image["id"] for image in payload["images"]}
                self.assertTrue(all(ann["image_id"] in image_ids for ann in payload["annotations"]))
                self.assertEqual(payload["categories"], [module.SHOE_CATEGORY])

    def test_main_runs_stage6_validation_and_writes_deterministic_split_outputs(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            self._create_dataset_roots(raw_dir)
            unified_dir.mkdir(parents=True, exist_ok=True)

            def make_adapter(dataset_name: str):
                dataset_prefix = self._dataset_prefix(dataset_name)

                def _fake_adapter(_dataset_dir: Path, start_image_id: int, start_annotation_id: int):
                    image = module.make_image(
                        start_image_id,
                        f"{dataset_prefix}/example_{start_image_id}.jpg",
                        10,
                        10,
                    )
                    annotation = module.make_annotation(
                        start_annotation_id,
                        start_image_id,
                        [[1, 1, 4, 1, 4, 4]],
                        [1, 1, 3, 3],
                        9,
                    )
                    return [image], [annotation], start_image_id + 1, start_annotation_id + 1

                return _fake_adapter

            stage2_adapters = {
                "kaggle_shoe_seg": make_adapter("kaggle_shoe_seg"),
                "kaggle_people_clothing": make_adapter("kaggle_people_clothing"),
                "ccp": make_adapter("ccp"),
            }
            stage3_adapters = {
                "modanet": make_adapter("modanet"),
                "imaterialist": make_adapter("imaterialist"),
            }
            stage4_adapters = {
                "openimages_seg": make_adapter("openimages_seg"),
            }
            stage5_adapters = {
                "atr": make_adapter("atr"),
            }

            with patch.object(module, "RAW_DIR", raw_dir), patch.object(
                module, "UNIFIED_DIR", unified_dir
            ), patch.object(
                module, "STAGE_2_ADAPTERS", stage2_adapters
            ), patch.object(
                module, "STAGE_3_ADAPTERS", stage3_adapters
            ), patch.object(
                module, "STAGE_4_ADAPTERS", stage4_adapters
            ), patch.object(
                module, "STAGE_5_ADAPTERS", stage5_adapters
            ), patch(
                "sys.argv", ["shoe_seg_normalize_to_coco.py"]
            ):
                first_exit_code = module.main()
                first_split_payloads = {
                    split_name: json.loads(
                        (unified_dir / f"split_{split_name}.json").read_text(encoding="utf-8")
                    )
                    for split_name in ("train", "val", "test")
                }

                second_exit_code = module.main()
                second_split_payloads = {
                    split_name: json.loads(
                        (unified_dir / f"split_{split_name}.json").read_text(encoding="utf-8")
                    )
                    for split_name in ("train", "val", "test")
                }

            self.assertEqual(first_exit_code, 0)
            self.assertEqual(second_exit_code, 0)
            self.assertEqual(first_split_payloads, second_split_payloads)
            merged_file_names = {
                image["file_name"]
                for payload in first_split_payloads.values()
                for image in payload["images"]
            }
            self.assertIn("modanet_images/example_1.jpg", merged_file_names)


if __name__ == "__main__":
    unittest.main()
