from __future__ import annotations

import builtins
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

import shoe_seg_atr_adapter
from test_shoe_seg_test_support import SCRIPT_PATH, ShoeSegNormalizeToCocoTestBase, load_module


class Stage5AtrAdapterTests(ShoeSegNormalizeToCocoTestBase):
    """Tests for Stage 5 ATR helper, adapter, and orchestration seams."""

    def test_atr_shoe_class_ids_match_stage5_pinned_values(self):
        self.assertEqual(shoe_seg_atr_adapter.ATR_SHOE_CLASS_IDS, {9, 10})

    def test_decode_atr_payload_bytes_supports_raw_and_hf_dict_bytes(self):
        raw_payload = b"raw-bytes"
        hf_payload = {"bytes": b"wrapped-bytes"}

        self.assertEqual(shoe_seg_atr_adapter._decode_atr_payload_bytes(raw_payload), raw_payload)
        self.assertEqual(
            shoe_seg_atr_adapter._decode_atr_payload_bytes(hf_payload), b"wrapped-bytes"
        )
        self.assertIsNone(
            shoe_seg_atr_adapter._decode_atr_payload_bytes({"bytes": "not-bytes"})
        )
        self.assertIsNone(shoe_seg_atr_adapter._decode_atr_payload_bytes(None))

    def test_atr_dependency_failures_are_local_to_atr_path(self):
        script_dir = str(SCRIPT_PATH.parent)

        real_import = builtins.__import__

        def _guarded_import(name, globals=None, locals=None, fromlist=(), level=0):
            if name == "pandas" or name.startswith("PIL"):
                raise ModuleNotFoundError(name)
            return real_import(name, globals, locals, fromlist, level)

        with patch("builtins.__import__", side_effect=_guarded_import):
            reloaded_module = load_module()

        self.assertEqual(reloaded_module.__file__, str(SCRIPT_PATH))
        self.assertIn(script_dir, __import__("sys").path)

        with tempfile.TemporaryDirectory() as tmp_dir:
            def _pandas_missing(name, globals=None, locals=None, fromlist=(), level=0):
                if name == "pandas":
                    raise ModuleNotFoundError(name)
                return real_import(name, globals, locals, fromlist, level)

            with patch("builtins.__import__", side_effect=_pandas_missing):
                with self.assertRaises(RuntimeError) as parquet_context:
                    list(reloaded_module.shoe_seg_atr_adapter._iter_atr_parquet_rows(Path(tmp_dir)))
            self.assertIn("pandas", str(parquet_context.exception).lower())

            def _pillow_missing(name, globals=None, locals=None, fromlist=(), level=0):
                if name == "PIL" or name.startswith("PIL."):
                    raise ModuleNotFoundError(name)
                return real_import(name, globals, locals, fromlist, level)

            with patch("builtins.__import__", side_effect=_pillow_missing):
                with self.assertRaises(RuntimeError) as pillow_context:
                    reloaded_module.shoe_seg_atr_adapter._load_atr_row_image_and_mask(
                        {"image": b"bad", "mask": b"bad"}
                    )
            self.assertIn("pillow", str(pillow_context.exception).lower())

    def test_build_atr_records_merges_shoe_classes_and_skips_invalid_rows(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "atr"
            (dataset_dir / "data").mkdir(parents=True, exist_ok=True)

            valid_rgb_1 = np.full((6, 8, 3), 60, dtype=np.uint8)
            valid_mask_1 = np.zeros((6, 8), dtype=np.uint8)
            valid_mask_1[1:3, 1:4] = 9
            valid_mask_1[3:5, 4:7] = 10

            valid_rgb_2 = np.full((5, 7, 3), 80, dtype=np.uint8)
            valid_mask_2 = np.zeros((5, 7), dtype=np.uint8)
            valid_mask_2[0:3, 0:2] = 10

            tiny_mask_rgb = np.full((4, 4, 3), 40, dtype=np.uint8)
            tiny_mask = np.zeros((4, 4), dtype=np.uint8)
            tiny_mask[0, 0] = 9

            rows = [
                {"row_id": "valid-1"},
                {"row_id": "missing"},
                {"row_id": "empty-mask"},
                {"row_id": "tiny-no-polygon"},
                {"row_id": "valid-2"},
            ]

            def _fake_iter_rows(data_dir: Path):
                self.assertEqual(data_dir, dataset_dir / "data")
                for row in rows:
                    yield row

            def _fake_load_row(row: dict[str, object]):
                row_id = row["row_id"]
                if row_id == "valid-1":
                    return valid_rgb_1, valid_mask_1
                if row_id == "valid-2":
                    return valid_rgb_2, valid_mask_2
                if row_id == "tiny-no-polygon":
                    return tiny_mask_rgb, tiny_mask
                if row_id == "empty-mask":
                    return np.full((3, 3, 3), 30, dtype=np.uint8), np.zeros((3, 3), dtype=np.uint8)
                return None

            with patch.object(
                module.shoe_seg_atr_adapter,
                "_iter_atr_parquet_rows",
                side_effect=_fake_iter_rows,
            ), patch.object(
                module.shoe_seg_atr_adapter,
                "_load_atr_row_image_and_mask",
                side_effect=_fake_load_row,
            ):
                images, annotations, next_image_id, next_annotation_id = module.build_atr_records(
                    dataset_dir=dataset_dir,
                    start_image_id=5,
                    start_annotation_id=20,
                )

            self.assertEqual([image["id"] for image in images], [5, 6])
            self.assertEqual([ann["id"] for ann in annotations], [20, 21])
            self.assertEqual(next_image_id, 7)
            self.assertEqual(next_annotation_id, 22)
            self.assertEqual(
                [image["file_name"] for image in images],
                [
                    "atr/extracted_images/atr_5.jpg",
                    "atr/extracted_images/atr_6.jpg",
                ],
            )
            self.assertTrue((dataset_dir / "extracted_images/atr_5.jpg").is_file())
            self.assertTrue((dataset_dir / "extracted_images/atr_6.jpg").is_file())

            merged_binary = np.zeros((6, 8), dtype=np.uint8)
            merged_binary[1:3, 1:4] = 1
            merged_binary[3:5, 4:7] = 1
            self.assertEqual(annotations[0]["area"], module.area_from_mask(merged_binary))
            self.assertEqual(annotations[0]["bbox"], module.bbox_from_mask(merged_binary))

    def test_build_atr_records_is_idempotent_and_round_trips_to_coco(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "atr"
            (dataset_dir / "data").mkdir(parents=True, exist_ok=True)

            rgb = np.full((4, 4, 3), 25, dtype=np.uint8)
            mask = np.zeros((4, 4), dtype=np.uint8)
            mask[1:3, 1:3] = 9

            rows = [{"row_id": "only"}]

            def _fake_iter_rows(_data_dir: Path):
                for row in rows:
                    yield row

            def _fake_load_row(_row: dict[str, object]):
                return rgb, mask

            with patch.object(
                module.shoe_seg_atr_adapter,
                "_iter_atr_parquet_rows",
                side_effect=_fake_iter_rows,
            ), patch.object(
                module.shoe_seg_atr_adapter,
                "_load_atr_row_image_and_mask",
                side_effect=_fake_load_row,
            ):
                first_images, first_annotations, _, _ = module.build_atr_records(
                    dataset_dir=dataset_dir,
                    start_image_id=1,
                    start_annotation_id=1,
                )
                second_images, second_annotations, _, _ = module.build_atr_records(
                    dataset_dir=dataset_dir,
                    start_image_id=1,
                    start_annotation_id=1,
                )

            extracted_files = sorted((dataset_dir / "extracted_images").glob("*.jpg"))
            self.assertEqual([path.name for path in extracted_files], ["atr_1.jpg"])
            self.assertEqual(first_images, second_images)
            self.assertEqual(first_annotations, second_annotations)

            output_path = Path(tmp_dir) / "atr.json"
            module.write_coco_json(first_images, first_annotations, output_path)
            payload = json.loads(output_path.read_text(encoding="utf-8"))

            self.assertEqual(payload["categories"], [module.SHOE_CATEGORY])
            self.assertEqual(payload["images"][0]["file_name"], "atr/extracted_images/atr_1.jpg")
            self.assertEqual(payload["annotations"][0]["category_id"], module.SHOE_CATEGORY["id"])

    def test_build_atr_records_refreshes_existing_extracted_image_for_same_id(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            dataset_dir = Path(tmp_dir) / "atr"
            (dataset_dir / "data").mkdir(parents=True, exist_ok=True)

            mask = np.zeros((4, 4), dtype=np.uint8)
            mask[1:3, 1:3] = 9
            rgb_values = [11, 22]
            write_calls: list[int] = []

            def _fake_iter_rows(_data_dir: Path):
                yield {"row_id": "only"}

            def _fake_load_row(_row: dict[str, object]):
                pixel_value = rgb_values.pop(0)
                rgb = np.full((4, 4, 3), pixel_value, dtype=np.uint8)
                return rgb, mask

            def _fake_write_rgb_jpg(path: Path, image_rgb: np.ndarray):
                path.parent.mkdir(parents=True, exist_ok=True)
                pixel_value = int(image_rgb[0, 0, 0])
                write_calls.append(pixel_value)
                path.write_bytes(bytes([pixel_value]))
                return True

            with patch.object(
                module.shoe_seg_atr_adapter,
                "_iter_atr_parquet_rows",
                side_effect=_fake_iter_rows,
            ), patch.object(
                module.shoe_seg_atr_adapter,
                "_load_atr_row_image_and_mask",
                side_effect=_fake_load_row,
            ), patch.object(
                module.shoe_seg_atr_adapter,
                "_write_rgb_jpg",
                side_effect=_fake_write_rgb_jpg,
            ):
                module.build_atr_records(
                    dataset_dir=dataset_dir,
                    start_image_id=1,
                    start_annotation_id=1,
                )
                module.build_atr_records(
                    dataset_dir=dataset_dir,
                    start_image_id=1,
                    start_annotation_id=1,
                )

            extracted_path = dataset_dir / "extracted_images/atr_1.jpg"
            self.assertEqual(write_calls, [11, 22])
            self.assertEqual(extracted_path.read_bytes(), bytes([22]))

    def test_build_stage_5_outputs_dispatches_atr_to_unified_json(self):
        module = self.module

        with tempfile.TemporaryDirectory() as tmp_dir:
            raw_dir = Path(tmp_dir) / "raw"
            unified_dir = Path(tmp_dir) / "unified"
            (raw_dir / "atr").mkdir(parents=True, exist_ok=True)
            unified_dir.mkdir(parents=True, exist_ok=True)

            fake_image = module.make_image(1, "atr/extracted_images/atr_1.jpg", 10, 10)
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

            with patch.object(
                module,
                "STAGE_5_ADAPTERS",
                {"atr": _fake_adapter},
            ), patch.object(module, "write_coco_json") as write_mock:
                module.build_stage_5_outputs(raw_dir=raw_dir, unified_dir=unified_dir)

            self.assertEqual(write_mock.call_count, 1)
            self.assertEqual(write_mock.call_args.args[2], unified_dir / "atr.json")

    def test_main_non_check_runs_stage_2_3_4_and_5(self):
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
                    "atr",
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
            written_paths = [call.args[2] for call in write_mock.call_args_list]
            self.assertIn(unified_dir / "atr.json", written_paths)


if __name__ == "__main__":
    unittest.main()
