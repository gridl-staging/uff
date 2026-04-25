#!/usr/bin/env python3
"""
Stub summary for /Users/stuart/parallel_development/uff_dev/MAR18_workstream_B_polish_widget_keys_e2e/uff_dev/scripts/segment_shoes.py.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageDraw


def get_device() -> torch.device:
    if torch.cuda.is_available():
        return torch.device("cuda")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def load_models(device: torch.device):
    """TODO: Document load_models."""
    from transformers import (
        AutoModelForZeroShotObjectDetection,
        AutoProcessor,
        SamModel,
        SamProcessor,
    )

    print("Loading Grounding DINO...", end=" ", flush=True)
    t0 = time.time()
    gdino_proc = AutoProcessor.from_pretrained("IDEA-Research/grounding-dino-tiny")
    gdino_model = AutoModelForZeroShotObjectDetection.from_pretrained(
        "IDEA-Research/grounding-dino-tiny"
    ).to(device)
    gdino_model.eval()
    print(f"({time.time() - t0:.1f}s)")

    print("Loading SAM...", end=" ", flush=True)
    t0 = time.time()
    sam_proc = SamProcessor.from_pretrained("facebook/sam-vit-large")
    sam_model = SamModel.from_pretrained("facebook/sam-vit-large").to(device)
    sam_model.eval()
    print(f"({time.time() - t0:.1f}s)")

    return gdino_proc, gdino_model, sam_proc, sam_model


def detect_shoes(image, gdino_proc, gdino_model, device, threshold=0.35):
    inputs = gdino_proc(images=image, text="shoe.", return_tensors="pt").to(device)
    with torch.no_grad():
        outputs = gdino_model(**inputs)

    w, h = image.size
    results = gdino_proc.post_process_grounded_object_detection(
        outputs,
        inputs.input_ids,
        threshold=threshold,
        text_threshold=0.25,
        target_sizes=[(h, w)],
    )
    return results[0]


def segment_shoes(image, boxes, sam_proc, sam_model, device):
    """TODO: Document segment_shoes."""
    if len(boxes) == 0:
        return np.zeros((0, image.size[1], image.size[0]), dtype=bool)

    boxes_list = boxes.cpu().tolist()
    inputs = sam_proc(image, input_boxes=[boxes_list], return_tensors="pt")
    # MPS doesn't support float64 — cast to float32 before moving to device
    inputs = {k: v.float().to(device) if torch.is_tensor(v) and v.is_floating_point() else v.to(device) if torch.is_tensor(v) else v for k, v in inputs.items()}

    with torch.no_grad():
        outputs = sam_model(**inputs)

    masks = sam_proc.image_processor.post_process_masks(
        outputs.pred_masks.cpu(),
        inputs["original_sizes"].cpu(),
        inputs["reshaped_input_sizes"].cpu(),
    )
    # SAM outputs 3 mask candidates per box — take the first (best for box prompts)
    raw = masks[0]
    if raw.ndim == 4:
        raw = raw[:, 0, :, :]
    return raw.numpy() > 0.5


def draw_output(image, boxes, scores, masks):
    """TODO: Document draw_output."""
    img = np.array(image, dtype=np.float64)

    # Translucent red overlay on all shoe masks
    red = np.array([255.0, 40.0, 40.0])
    for mask in masks:
        img[mask] = 0.45 * red + 0.55 * img[mask]

    result = Image.fromarray(img.astype(np.uint8))

    # Draw bounding boxes and scores
    draw = ImageDraw.Draw(result)
    for i, (box, score) in enumerate(zip(boxes.cpu().tolist(), scores.cpu().tolist())):
        x1, y1, x2, y2 = box
        draw.rectangle([x1, y1, x2, y2], outline=(255, 50, 50), width=3)
        draw.text((x1, max(0, y1 - 14)), f"shoe {score:.0%}", fill=(255, 50, 50))

    return result


def main():
    """TODO: Document main."""
    parser = argparse.ArgumentParser(description="Segment shoes in any image.")
    parser.add_argument("image", help="Path to input image")
    parser.add_argument("-o", "--output", help="Output path (default: <input>_shoes.png)")
    parser.add_argument(
        "--threshold", type=float, default=0.35,
        help="Detection confidence threshold (default: 0.35)",
    )
    args = parser.parse_args()

    img_path = Path(args.image)
    if not img_path.exists():
        print(f"Error: {img_path} not found")
        sys.exit(1)

    if args.output:
        out_path = Path(args.output)
    else:
        out_path = img_path.with_stem(img_path.stem + "_shoes").with_suffix(".png")

    image = Image.open(img_path).convert("RGB")
    print(f"Input: {img_path} ({image.size[0]}x{image.size[1]})")

    device = get_device()
    print(f"Device: {device}")

    gdino_proc, gdino_model, sam_proc, sam_model = load_models(device)

    print("Detecting shoes...", end=" ", flush=True)
    t0 = time.time()
    detections = detect_shoes(image, gdino_proc, gdino_model, device, args.threshold)
    boxes = detections["boxes"]
    scores = detections["scores"]
    n = len(boxes)
    print(f"found {n} shoe{'s' if n != 1 else ''} ({time.time() - t0:.1f}s)")

    if n == 0:
        print("No shoes detected. Try lowering --threshold (e.g. 0.2)")
        sys.exit(0)

    for i, s in enumerate(scores.cpu().tolist()):
        print(f"  shoe {i + 1}: {s:.0%} confidence")

    print("Segmenting...", end=" ", flush=True)
    t0 = time.time()
    masks = segment_shoes(image, boxes, sam_proc, sam_model, device)
    print(f"done ({time.time() - t0:.1f}s)")

    result = draw_output(image, boxes, scores, masks)
    result.save(out_path)
    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
