#!/usr/bin/env python3
"""
Stub summary for /Users/stuart/parallel_development/uff_dev/MAR18_workstream_B_polish_widget_keys_e2e/uff_dev/scripts/runpod_setup_data.py.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

WORKSPACE = Path("/workspace")
COCO_EXPORT_DIR = WORKSPACE / "coco_export"
DFINE_DIR = WORKSPACE / "D-FINE"
RAW_DIR = WORKSPACE / "data/shoe_seg/raw"
UNIFIED_DIR = WORKSPACE / "data/shoe_seg/unified"
LOGS_DIR = WORKSPACE / "logs"
CACHE_DIR = WORKSPACE / ".cache"


def _redirect_caches_to_workspace() -> None:
    """Move all tool caches to /workspace to avoid filling the container disk."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    (WORKSPACE / "tmp").mkdir(exist_ok=True)
    os.environ.setdefault("TMPDIR", str(WORKSPACE / "tmp"))
    os.environ.setdefault("KAGGLE_CACHE_FOLDER", str(CACHE_DIR / "kagglehub"))
    os.environ.setdefault("HF_HOME", str(CACHE_DIR / "huggingface"))
    os.environ.setdefault("FIFTYONE_DATABASE_DIR", str(CACHE_DIR / "fiftyone_db"))
    os.environ.setdefault("FIFTYONE_DEFAULT_DATASET_DIR", str(CACHE_DIR / "fiftyone_data"))


def _run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    print(f"  $ {' '.join(cmd[:6])}{'...' if len(cmd) > 6 else ''}")
    return subprocess.run(cmd, check=True, **kwargs)


def _dir_size(path: Path) -> str:
    result = subprocess.run(["du", "-sh", str(path)], capture_output=True, text=True)
    return result.stdout.split()[0] if result.returncode == 0 else "?"


# ── 1. Dependencies ────────────────────────────────────────────────────────


def install_deps() -> None:
    _run([
        sys.executable, "-m", "pip", "install", "-q",
        "fiftyone", "kagglehub", "huggingface_hub",
        "pycocotools", "opencv-python-headless",
        "pandas", "pyarrow", "pillow", "numpy", "tqdm",
    ])


# ── 2. D-FINE setup ───────────────────────────────────────────────────────


def setup_dfine() -> None:
    if not DFINE_DIR.exists():
        _run(["git", "clone", "https://github.com/Peterande/D-FINE", str(DFINE_DIR)])

    checkpoint = DFINE_DIR / "dfine_s_obj365.pth"
    if not checkpoint.exists():
        _run([
            "curl", "-L", "-o", str(checkpoint),
            "https://github.com/Peterande/storage/releases/download/dfinev1.0/dfine_s_obj365.pth",
        ])

    reqs = DFINE_DIR / "requirements.txt"
    if reqs.exists():
        _run([sys.executable, "-m", "pip", "install", "-q", "-r", str(reqs)])


# ── 3. Detection data ─────────────────────────────────────────────────────


def download_detection_data() -> None:
    """Download OI V7 footwear via FiftyOne and export to COCO format."""
    if (COCO_EXPORT_DIR / "train" / "labels.json").exists():
        print("  COCO export already exists, skipping")
        return

    import fiftyone as fo
    import fiftyone.zoo as foz

    fo.config.dataset_zoo_dir = str(WORKSPACE / "fiftyone_zoo")

    ds_name = "uff-shoes-detection"
    if fo.dataset_exists(ds_name):
        dataset = fo.load_dataset(ds_name)
    else:
        dataset = foz.load_zoo_dataset(
            "open-images-v7",
            split="train",
            label_types=["detections"],
            classes=["Footwear"],
            dataset_name=ds_name,
        )

    print(f"  Detection dataset: {len(dataset)} samples")

    shuffled = dataset.shuffle(seed=42)
    split_at = min(16000, len(shuffled))
    train, val = shuffled[:split_at], shuffled[split_at:]

    train.export(
        export_dir=str(COCO_EXPORT_DIR / "train"),
        dataset_type=fo.types.COCODetectionDataset,
        label_field="ground_truth",
    )
    val.export(
        export_dir=str(COCO_EXPORT_DIR / "val"),
        dataset_type=fo.types.COCODetectionDataset,
        label_field="ground_truth",
    )

    print(f"  COCO export done: train={len(train)}, val={len(val)}")


# ── 4. Segmentation datasets ──────────────────────────────────────────────


def _kaggle(dataset_id: str, target_name: str) -> None:
    target = RAW_DIR / target_name
    if target.exists() and any(target.iterdir()):
        print(f"  {target_name}: exists, skipping")
        return

    import kagglehub

    path = kagglehub.dataset_download(dataset_id)
    if target.exists():
        shutil.rmtree(target)
    # Use move instead of copytree to avoid doubling data on NFS volumes
    shutil.move(str(path), str(target))
    print(f"  {target_name}: {_dir_size(target)}")


def _huggingface(repo_id: str, target_name: str) -> None:
    target = RAW_DIR / target_name
    if target.exists() and any(target.iterdir()):
        print(f"  {target_name}: exists, skipping")
        return

    from huggingface_hub import snapshot_download

    snapshot_download(repo_id=repo_id, repo_type="dataset", local_dir=str(target))
    print(f"  {target_name}: {_dir_size(target)}")


def _openimages_seg() -> None:
    """Download OpenImages V7 segmentation data (Boot + High heels).

    FiftyOne downloads ALL 16 mask shard ZIPs (2.7M+ tiny PNG files).
    RunPod's NFS volume has a file-count quota that this exceeds.
    Skip if the quota is hit — this dataset can be added later via a
    targeted downloader that only fetches the ~2,700 relevant masks.
    """
    target = RAW_DIR / "openimages_seg"
    if (target / "open-images-v7").exists():
        print("  openimages_seg: exists, skipping")
        return

    import fiftyone as fo
    import fiftyone.zoo as foz

    fo.config.dataset_zoo_dir = str(target)

    try:
        for split in ("train", "validation"):
            name = f"uff-shoes-seg-{split}"
            if fo.dataset_exists(name):
                ds = fo.load_dataset(name)
            else:
                ds = foz.load_zoo_dataset(
                    "open-images-v7",
                    split=split,
                    label_types=["segmentations"],
                    classes=["Boot", "High heels", "Sandal"],
                    dataset_name=name,
                )
            print(f"  openimages_seg/{split}: {len(ds)} samples")
    except OSError as exc:
        if "Disk quota" in str(exc) or "No space" in str(exc):
            print(
                f"  openimages_seg: SKIPPED — disk quota exceeded ({exc}). "
                "FiftyOne downloads 2.7M+ mask files which exceeds RunPod NFS limits. "
                "This dataset can be added later via a targeted downloader."
            )
        else:
            raise


def _modanet() -> None:
    """TODO: Document _modanet."""
    coco_dir = RAW_DIR / "modanet_images" / "datasets" / "coco"
    images_dir = coco_dir / "images"
    ann_file = coco_dir / "annotations" / "instances_all.json"

    if (
        images_dir.exists()
        and len(list(images_dir.iterdir())) > 1000
        and ann_file.exists()
    ):
        print("  modanet: exists, skipping")
        return

    coco_dir.mkdir(parents=True, exist_ok=True)
    (coco_dir / "annotations").mkdir(exist_ok=True)

    images_zip = coco_dir / "images.zip"
    if not images_zip.exists():
        print("  modanet: downloading images.zip (2 GB)...")
        _run([
            "wget", "-O", str(images_zip),
            "https://github.com/cad0p/maskrcnn-modanet/releases/download/v0.9/images.zip",
        ])

    if not images_dir.exists() or len(list(images_dir.iterdir())) < 1000:
        print("  modanet: extracting images...")
        _run(["unzip", "-q", "-o", str(images_zip), "-d", str(coco_dir)])

    if not ann_file.exists():
        print("  modanet: downloading annotations...")
        _run([
            "wget", "-q", "-O", str(ann_file),
            "https://github.com/cad0p/maskrcnn-modanet/releases/download/v0.9/instances_all.json",
        ])

    print(f"  modanet: {_dir_size(RAW_DIR / 'modanet_images')}")


def download_seg_data() -> None:
    """TODO: Document download_seg_data."""
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    UNIFIED_DIR.mkdir(parents=True, exist_ok=True)

    print("  Kaggle datasets...")
    _kaggle(
        "ilsafshamsutdinov/shoes-dataset-for-semantic-segmentation",
        "kaggle_shoe_seg",
    )
    _kaggle("rajkumarl/people-clothing-segmentation", "kaggle_people_clothing")
    _kaggle(
        "sknahin/imaterialist-fashion-yolo-segmentation-dataset",
        "imaterialist",
    )
    _kaggle("balraj98/clothing-coparsing-dataset", "ccp")

    print("  HuggingFace datasets...")
    _huggingface("mattmdjaga/human_parsing_dataset", "atr")

    print("  OpenImages segmentation...")
    _openimages_seg()

    print("  ModaNet...")
    _modanet()


# ── Verification ───────────────────────────────────────────────────────────


def verify() -> None:
    """TODO: Document verify."""
    print("\nData summary:")
    required = [
        ("COCO export (det)", COCO_EXPORT_DIR),
        ("D-FINE code", DFINE_DIR),
        ("kaggle_shoe_seg", RAW_DIR / "kaggle_shoe_seg"),
        ("kaggle_people_clothing", RAW_DIR / "kaggle_people_clothing"),
        ("modanet_images", RAW_DIR / "modanet_images"),
        ("imaterialist", RAW_DIR / "imaterialist"),
        ("ccp", RAW_DIR / "ccp"),
        ("atr", RAW_DIR / "atr"),
    ]
    optional = [
        ("openimages_seg", RAW_DIR / "openimages_seg"),
    ]
    all_ok = True
    for name, path in required:
        if path.exists():
            print(f"  OK  {name}: {_dir_size(path)}")
        else:
            print(f"  MISSING  {name}")
            all_ok = False
    for name, path in optional:
        if path.exists():
            print(f"  OK  {name}: {_dir_size(path)}")
        else:
            print(f"  SKIP  {name} (optional — can be added later)")
    if not all_ok:
        raise RuntimeError("Some required datasets are missing — check output above")


# ── Main ───────────────────────────────────────────────────────────────────


def main() -> int:
    """TODO: Document main."""
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    _redirect_caches_to_workspace()

    # Remove partial upload leftovers from previous attempts
    for leftover in ("coco_export.tar.gz", "dfine_bundle.tar.gz"):
        path = WORKSPACE / leftover
        if path.exists():
            print(f"Removing leftover: {path}")
            path.unlink()

    print("=== 1/4 Installing dependencies ===")
    install_deps()

    print("\n=== 2/4 Setting up D-FINE ===")
    setup_dfine()

    print("\n=== 3/4 Detection data (OI V7 footwear -> COCO export) ===")
    download_detection_data()

    print("\n=== 4/4 Segmentation datasets (7 sources) ===")
    download_seg_data()

    verify()
    print("\nSetup complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
