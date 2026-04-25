#!/usr/bin/env python3
"""
Stub summary for /Users/stuart/parallel_development/uff_dev/MAR18_workstream_B_polish_widget_keys_e2e/uff_dev/scripts/run_zero_shot_eval.py.
"""

from __future__ import annotations

import argparse
import random
import shlex
import subprocess

import tempfile
import time
from pathlib import Path

import runpod

REPO = Path(__file__).resolve().parents[1]

# Auth
ENV_SECRET_PATH = REPO / ".secret/.env.secret"
DEFAULT_SSH_KEY_PATH = REPO / ".secret/.runpod"
RUNPOD_KEY_NAME = "runpod_stuart_key_mar9"

# Local data paths
KAGGLE_SHOE_SEG = REPO / "data/shoe_seg/raw/kaggle_shoe_seg/shoes_dataset"
KAGGLE_CLOTHING = REPO / "data/shoe_seg/raw/kaggle_people_clothing/jpeg_images/IMAGES"
OPEN_IMAGES = REPO / "data/shoe_detection/open-images-v7/train/data"

# Script to upload
EVAL_SCRIPT = REPO / "scripts/eval_zero_shot_shoes.py"

# Local output
OUTPUT_DIR = REPO / "data/models/zero_shot_eval"

# Pod config
DEFAULT_GPU_TYPE = "NVIDIA GeForce RTX 4090"
DEFAULT_DOCKER_IMAGE = "runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04"


# ── Helpers (reused from train_dfine.py) ───────────────────────────────────


def load_runpod_key(env_path: Path, key_name: str) -> str:
    with env_path.open("r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith(f"{key_name}="):
                return s.split("=", 1)[1]
    raise RuntimeError(f"Key '{key_name}' not found in {env_path}")


def run_cmd(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, check=check, capture_output=True)


def run_cmd_live(cmd: list[str]) -> int:
    proc = subprocess.Popen(cmd)
    proc.wait()
    return proc.returncode


def run_ssh(ssh_base: list[str], remote_cmd: str, *, check: bool = True) -> int:
    cmd = ssh_base + [remote_cmd]
    if check:
        subprocess.run(cmd, text=True, check=True)
        return 0
    return run_cmd_live(cmd)


def wait_for_ssh(ssh_base: list[str], timeout: int = 300) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        probe = subprocess.run(ssh_base + ["echo SSH_OK"], text=True, capture_output=True)
        if probe.returncode == 0 and "SSH_OK" in probe.stdout:
            return
        print("  SSH not ready, retrying...")
        time.sleep(10)
    raise TimeoutError("SSH login timed out")


def wait_for_endpoint(pod_id: str, timeout: int = 600) -> tuple[str, int]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = runpod.get_pod(pod_id)
        runtime = status.get("runtime") or {}
        for port in runtime.get("ports") or []:
            if port.get("privatePort") == 22 and port.get("isIpPublic"):
                ip = port.get("ip")
                pub = port.get("publicPort")
                if ip and pub:
                    return str(ip), int(pub)
        print("  Waiting for SSH endpoint...")
        time.sleep(10)
    raise TimeoutError(f"Pod SSH endpoint timed out: {pod_id}")


def build_ssh_base(ip: str, port: int, key: Path) -> list[str]:
    return [
        "ssh", f"root@{ip}", "-p", str(port), "-i", str(key),
        "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=30",
        "-o", "ConnectionAttempts=5", "-o", "ServerAliveInterval=60",
        "-o", "ServerAliveCountMax=10",
    ]


def build_scp_base(ip: str, port: int, key: Path) -> list[str]:
    return [
        "scp", "-q", "-P", str(port), "-i", str(key),
        "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=30",
    ]


# ── Test image sampling ───────────────────────────────────────────────────


def sample_test_images(staging_dir: Path) -> int:
    """Copy sampled test images to staging directory. Returns total count."""
    import shutil

    staging_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    exts = {".jpg", ".jpeg", ".png"}

    # All kaggle_shoe_seg images (product shots — should be easy to detect)
    for subdir in ["train/images", "valid/images"]:
        src = KAGGLE_SHOE_SEG / subdir
        if src.exists():
            for img in src.iterdir():
                if img.suffix.lower() in exts:
                    # Prefix to track source
                    dst = staging_dir / f"shoeseg_{img.name}"
                    shutil.copy2(img, dst)
                    count += 1
    print(f"  kaggle_shoe_seg: {count} images")

    # Sample from clothing dataset (shoes on people)
    clothing_count = 0
    if KAGGLE_CLOTHING.exists():
        all_clothing = [p for p in KAGGLE_CLOTHING.iterdir() if p.suffix.lower() in exts]
        sample = random.sample(all_clothing, min(25, len(all_clothing)))
        for img in sample:
            shutil.copy2(img, staging_dir / f"clothing_{img.name}")
            clothing_count += 1
    print(f"  kaggle_people_clothing: {clothing_count} images")
    count += clothing_count

    # Sample from open-images (general footwear)
    oi_count = 0
    if OPEN_IMAGES.exists():
        all_oi = [p for p in OPEN_IMAGES.iterdir() if p.suffix.lower() in exts]
        sample = random.sample(all_oi, min(18, len(all_oi)))
        for img in sample:
            shutil.copy2(img, staging_dir / f"openimg_{img.name}")
            oi_count += 1
    print(f"  open-images: {oi_count} images")
    count += oi_count

    print(f"  TOTAL: {count} test images")
    return count


# ── Main ───────────────────────────────────────────────────────────────────


def main() -> int:
    """TODO: Document main."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pod-id", default=None, help="Connect to existing pod")
    parser.add_argument("--keep-pod", action="store_true", help="Don't terminate after")
    parser.add_argument("--gpu-type", default=DEFAULT_GPU_TYPE)
    parser.add_argument("--docker-image", default=DEFAULT_DOCKER_IMAGE)
    parser.add_argument("--ssh-key-path", default=None)
    args = parser.parse_args()

    ssh_key = Path(args.ssh_key_path) if args.ssh_key_path else DEFAULT_SSH_KEY_PATH
    ssh_pub = ssh_key.with_suffix(".pub")
    for p in [ssh_key, ssh_pub, ENV_SECRET_PATH, EVAL_SCRIPT]:
        if not p.exists():
            print(f"ERROR: Missing {p}")
            return 1

    runpod.api_key = load_runpod_key(ENV_SECRET_PATH, RUNPOD_KEY_NAME)
    print(f"RunPod API key loaded: {runpod.api_key[:10]}...")
    ssh_pub_text = ssh_pub.read_text().strip()

    # ── Stage test images ──────────────────────────────────────────
    print("\nSampling test images...")
    random.seed(42)  # reproducible sample
    staging = Path(tempfile.mkdtemp(prefix="shoe_eval_"))
    n_images = sample_test_images(staging)
    if n_images == 0:
        print("ERROR: No test images found")
        return 1

    # Create tarball for fast upload
    tar_path = staging.parent / "shoe_eval_images.tar.gz"
    print(f"\nCreating tarball: {tar_path}")
    subprocess.run(
        ["tar", "czf", str(tar_path), "--exclude", "._*", "-C", str(staging), "."],
        check=True,
    )
    tar_size_mb = tar_path.stat().st_size / (1024 * 1024)
    print(f"  Tarball size: {tar_size_mb:.1f} MB")

    pod_id: str | None = None
    ssh_ip: str | None = None
    ssh_port: int | None = None

    try:
        # ── Create or connect to pod ───────────────────────────────
        if args.pod_id:
            pod_id = args.pod_id
            print(f"\nConnecting to existing pod: {pod_id}")
            ssh_ip, ssh_port = wait_for_endpoint(pod_id)
        else:
            print(f"\nCreating RunPod pod (GPU: {args.gpu_type})...")
            pod = runpod.create_pod(
                name="shoe-zero-shot-eval",
                image_name=args.docker_image,
                gpu_type_id=args.gpu_type,
                gpu_count=1,
                volume_in_gb=20,  # minimal — we're just evaluating
                volume_mount_path="/workspace",
                container_disk_in_gb=30,
                ports="22/tcp",
                support_public_ip=True,
                start_ssh=True,
                cloud_type="ALL",
                env={"PUBLIC_KEY": ssh_pub_text},
            )
            pod_id = pod["id"]
            print(f"  Pod created: {pod_id}")
            ssh_ip, ssh_port = wait_for_endpoint(pod_id)

        ssh_base = build_ssh_base(ssh_ip, ssh_port, ssh_key)
        scp_base = build_scp_base(ssh_ip, ssh_port, ssh_key)

        print("Waiting for SSH login...")
        wait_for_ssh(ssh_base)
        print(f"  SSH ready: root@{ssh_ip}:{ssh_port}")

        # ── Upload eval script + test images ───────────────────────
        print("\nUploading eval script...")
        run_ssh(ssh_base, "mkdir -p /workspace/test_images /workspace/eval_output")
        subprocess.run(
            scp_base + [str(EVAL_SCRIPT), f"root@{ssh_ip}:/workspace/eval_zero_shot_shoes.py"],
            check=True,
        )

        print(f"Uploading test images ({tar_size_mb:.1f} MB)...")
        subprocess.run(
            scp_base + [str(tar_path), f"root@{ssh_ip}:/workspace/shoe_eval_images.tar.gz"],
            check=True,
        )
        run_ssh(
            ssh_base,
            "cd /workspace/test_images && tar xzf /workspace/shoe_eval_images.tar.gz",
        )

        # ── Install dependencies + run eval ────────────────────────
        print("\nInstalling dependencies and running evaluation...")
        remote_script = """
set -euo pipefail

echo "=== GPU info ==="
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

echo "=== Installing deps ==="
pip install -q transformers Pillow numpy

echo "=== Test images ==="
ls /workspace/test_images/ | wc -l
echo "images ready"

echo "=== Running evaluation ==="
python /workspace/eval_zero_shot_shoes.py \
    --input-dir /workspace/test_images \
    --output-dir /workspace/eval_output \
    --text-prompts "shoe.,running shoe.,footwear." \
    --box-threshold 0.3 \
    --text-threshold 0.25
"""
        exit_code = run_ssh(
            ssh_base,
            "bash -lc " + shlex.quote(remote_script),
            check=False,
        )

        if exit_code != 0:
            print(f"\nWARNING: Eval script exited with code {exit_code}")
            print("Attempting to download partial results...")

        # ── Download results ───────────────────────────────────────
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        print(f"\nDownloading results to {OUTPUT_DIR}...")

        # Tar up results on pod for fast download
        run_ssh(
            ssh_base,
            "cd /workspace && tar czf eval_results.tar.gz eval_output/",
            check=False,
        )
        subprocess.run(
            scp_base + [f"root@{ssh_ip}:/workspace/eval_results.tar.gz", str(OUTPUT_DIR.parent / "eval_results.tar.gz")],
            check=True,
        )
        subprocess.run(
            ["tar", "xzf", str(OUTPUT_DIR.parent / "eval_results.tar.gz"),
             "-C", str(OUTPUT_DIR.parent)],
            check=True,
        )
        # Move extracted eval_output contents into our target dir
        extracted = OUTPUT_DIR.parent / "eval_output"
        if extracted.exists() and extracted != OUTPUT_DIR:
            import shutil
            if OUTPUT_DIR.exists():
                shutil.rmtree(OUTPUT_DIR)
            shutil.move(str(extracted), str(OUTPUT_DIR))

        # Print summary
        metrics_path = OUTPUT_DIR / "eval_metrics.json"
        if metrics_path.exists():
            with open(metrics_path) as f:
                metrics = json.load(f)
            print("\n" + "=" * 60)
            print("RESULTS DOWNLOADED SUCCESSFULLY")
            print("=" * 60)
            summary = metrics.get("summary", {})
            for k, v in summary.items():
                print(f"  {k}: {v}")
            print(f"\n  Annotated images: {OUTPUT_DIR / 'annotated'}")
            print(f"  Masks: {OUTPUT_DIR / 'masks'}")
            print(f"  Full metrics: {metrics_path}")
        else:
            print("WARNING: eval_metrics.json not found in downloaded results")

        return 0 if exit_code == 0 else 1

    finally:
        # Cleanup local temp files
        import shutil
        shutil.rmtree(staging, ignore_errors=True)
        tar_path.unlink(missing_ok=True)

        if pod_id and not args.keep_pod:
            print(f"\nTerminating pod: {pod_id}")
            try:
                runpod.terminate_pod(pod_id)
            except Exception as e:
                print(f"WARNING: Failed to terminate pod: {e}")
        elif pod_id and args.keep_pod:
            print(f"\nPod left running: {pod_id}")
            print(f"  SSH: ssh root@{ssh_ip} -p {ssh_port} -i {ssh_key}")


if __name__ == "__main__":
    import json
    raise SystemExit(main())
