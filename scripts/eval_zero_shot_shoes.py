#!/usr/bin/env python3
"""
Stub summary for /Users/stuart/parallel_development/uff_dev/MAR18_workstream_B_polish_widget_keys_e2e/uff_dev/scripts/eval_zero_shot_shoes.py.
"""

from __future__ import annotations

import argparse
import json

import sys
import time
from pathlib import Path

import numpy as np
import torch
from PIL import Image


# ── Model loading ──────────────────────────────────────────────────────────


def load_gdino(device: torch.device):
    """Load Grounding DINO from HuggingFace transformers."""
    from transformers import AutoProcessor, AutoModelForZeroShotObjectDetection

    model_id = "IDEA-Research/grounding-dino-tiny"
    print(f"Loading Grounding DINO: {model_id}")
    processor = AutoProcessor.from_pretrained(model_id)
    model = AutoModelForZeroShotObjectDetection.from_pretrained(model_id).to(device)
    model.eval()
    return processor, model


def load_sam(device: torch.device):
    """Load SAM from HuggingFace transformers."""
    from transformers import SamModel, SamProcessor

    model_id = "facebook/sam-vit-large"
    print(f"Loading SAM: {model_id}")
    processor = SamProcessor.from_pretrained(model_id)
    model = SamModel.from_pretrained(model_id).to(device)
    model.eval()
    return processor, model


# ── Inference ──────────────────────────────────────────────────────────────


def detect_shoes(
    image: Image.Image,
    gdino_processor,
    gdino_model,
    device: torch.device,
    text_prompt: str = "shoe.",
    box_threshold: float = 0.3,
    text_threshold: float = 0.25,
) -> dict:
    """Run Grounding DINO to detect shoes. Returns boxes, scores, labels."""
    inputs = gdino_processor(images=image, text=text_prompt, return_tensors="pt").to(device)
    with torch.no_grad():
        outputs = gdino_model(**inputs)

    w, h = image.size
    results = gdino_processor.post_process_grounded_object_detection(
        outputs,
        inputs.input_ids,
        threshold=box_threshold,
        text_threshold=text_threshold,
        target_sizes=[(h, w)],
    )
    return results[0]  # single image


def segment_with_sam(
    image: Image.Image,
    boxes: torch.Tensor,
    sam_processor,
    sam_model,
    device: torch.device,
) -> np.ndarray:
    """Run SAM with box prompts to get segmentation masks.

    Returns: (N, H, W) boolean mask array.
    """
    if len(boxes) == 0:
        return np.zeros((0, image.size[1], image.size[0]), dtype=bool)

    # SAM expects boxes as list of [x1, y1, x2, y2]
    boxes_list = boxes.cpu().tolist()
    # SamProcessor expects input_boxes as [[[x1,y1,x2,y2], ...]] (batch of lists)
    inputs = sam_processor(
        image, input_boxes=[boxes_list], return_tensors="pt"
    ).to(device)

    with torch.no_grad():
        outputs = sam_model(**inputs)

    # Post-process masks to original image size
    masks = sam_processor.image_processor.post_process_masks(
        outputs.pred_masks.cpu(),
        inputs["original_sizes"].cpu(),
        inputs["reshaped_input_sizes"].cpu(),
    )
    # masks[0] shape: (num_boxes, num_masks_per_box, H, W)
    # SAM outputs 3 mask candidates per box — take index 0 (best for box prompts)
    raw = masks[0]  # (num_boxes, num_masks_per_box, H, W)
    if raw.ndim == 4:
        raw = raw[:, 0, :, :]  # select best mask per box → (N, H, W)
    mask_array = raw.numpy() > 0.5
    return mask_array


# ── Visualization ──────────────────────────────────────────────────────────


def draw_results(
    image: Image.Image,
    boxes: torch.Tensor,
    scores: torch.Tensor,
    masks: np.ndarray,
) -> Image.Image:
    """Draw bounding boxes and semi-transparent masks on the image."""
    img_np = np.array(image).copy()

    # Draw masks with semi-transparent overlay
    colors = [
        (255, 0, 0),
        (0, 255, 0),
        (0, 0, 255),
        (255, 255, 0),
        (255, 0, 255),
        (0, 255, 255),
    ]
    for i, mask in enumerate(masks):
        color = np.array(colors[i % len(colors)], dtype=np.float64)
        # mask is (H, W) boolean; img_np is (H, W, 3)
        alpha = 0.5
        img_np[mask] = (alpha * color + (1 - alpha) * img_np[mask].astype(np.float64)).astype(np.uint8)

    # Draw boxes and scores
    try:
        from PIL import ImageDraw, ImageFont

        draw = ImageDraw.Draw(Image.fromarray(img_np))
        for i, (box, score) in enumerate(zip(boxes.cpu().tolist(), scores.cpu().tolist())):
            x1, y1, x2, y2 = box
            color = colors[i % len(colors)]
            draw.rectangle([x1, y1, x2, y2], outline=color, width=3)
            label = f"shoe {score:.2f}"
            draw.text((x1, max(0, y1 - 15)), label, fill=color)
        return draw._image
    except Exception:
        return Image.fromarray(img_np)


# ── Main evaluation loop ──────────────────────────────────────────────────


def collect_images(input_dir: Path) -> list[Path]:
    """Find all image files in input directory (non-recursive)."""
    exts = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
    images = sorted(
        p for p in input_dir.iterdir() if p.suffix.lower() in exts and p.is_file()
    )
    return images


def evaluate(args: argparse.Namespace) -> dict:
    """TODO: Document evaluate."""
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "annotated").mkdir(exist_ok=True)
    (output_dir / "masks").mkdir(exist_ok=True)

    images = collect_images(input_dir)
    if not images:
        print(f"ERROR: No images found in {input_dir}")
        sys.exit(1)
    print(f"Found {len(images)} test images in {input_dir}")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    # Load models
    t0 = time.time()
    gdino_processor, gdino_model = load_gdino(device)
    sam_processor, sam_model = load_sam(device)
    load_time = time.time() - t0
    print(f"Models loaded in {load_time:.1f}s")

    # Run evaluation
    results = []
    total_detections = 0
    images_with_shoes = 0
    total_inference_time = 0.0

    text_prompts = args.text_prompts.split(",")

    for idx, img_path in enumerate(images):
        print(f"[{idx + 1}/{len(images)}] {img_path.name}", end=" ")
        try:
            image = Image.open(img_path).convert("RGB")
        except Exception as e:
            print(f"SKIP (load error: {e})")
            results.append({"file": img_path.name, "error": str(e)})
            continue

        best_result = None
        best_count = 0
        best_prompt = ""

        t_start = time.time()

        # Try each text prompt, keep the one that finds the most shoes
        for prompt in text_prompts:
            det = detect_shoes(
                image,
                gdino_processor,
                gdino_model,
                device,
                text_prompt=prompt.strip(),
                box_threshold=args.box_threshold,
                text_threshold=args.text_threshold,
            )
            n = len(det["boxes"])
            if n > best_count:
                best_count = n
                best_result = det
                best_prompt = prompt.strip()

        if best_result is None or best_count == 0:
            # No detections with any prompt
            t_elapsed = time.time() - t_start
            total_inference_time += t_elapsed
            print(f"→ 0 detections ({t_elapsed:.2f}s)")
            results.append({
                "file": img_path.name,
                "detections": 0,
                "scores": [],
                "prompt": "",
                "inference_ms": round(t_elapsed * 1000),
            })
            # Save original image with "NO DETECTION" label to annotated dir
            image.save(output_dir / "annotated" / img_path.name)
            continue

        boxes = best_result["boxes"]
        scores = best_result["scores"]

        # Run SAM segmentation on detected boxes
        masks = segment_with_sam(image, boxes, sam_processor, sam_model, device)
        t_elapsed = time.time() - t_start
        total_inference_time += t_elapsed

        num_det = len(boxes)
        total_detections += num_det
        images_with_shoes += 1
        score_list = scores.cpu().tolist()

        print(
            f"→ {num_det} shoe(s), scores={[f'{s:.2f}' for s in score_list]}, "
            f"prompt='{best_prompt}' ({t_elapsed:.2f}s)"
        )

        results.append({
            "file": img_path.name,
            "detections": num_det,
            "scores": [round(s, 4) for s in score_list],
            "boxes": boxes.cpu().tolist(),
            "prompt": best_prompt,
            "inference_ms": round(t_elapsed * 1000),
        })

        # Save annotated image
        annotated = draw_results(image, boxes, scores, masks)
        annotated.save(output_dir / "annotated" / img_path.name)

        # Save individual masks as PNGs (for quality inspection)
        for m_idx, mask in enumerate(masks):
            mask_img = Image.fromarray((mask * 255).astype(np.uint8))
            mask_img.save(output_dir / "masks" / f"{img_path.stem}_mask{m_idx}.png")

    # Summary stats
    n_images = len(images)
    n_errors = sum(1 for r in results if "error" in r)
    n_valid = n_images - n_errors
    detection_rate = images_with_shoes / n_valid if n_valid > 0 else 0
    avg_detections = total_detections / n_valid if n_valid > 0 else 0
    all_scores = [s for r in results for s in r.get("scores", [])]
    avg_score = sum(all_scores) / len(all_scores) if all_scores else 0
    avg_inference_ms = (total_inference_time / n_valid * 1000) if n_valid > 0 else 0

    summary = {
        "total_images": n_images,
        "errors": n_errors,
        "valid_images": n_valid,
        "images_with_detections": images_with_shoes,
        "detection_rate": round(detection_rate, 4),
        "total_detections": total_detections,
        "avg_detections_per_image": round(avg_detections, 2),
        "avg_confidence": round(avg_score, 4),
        "avg_inference_ms": round(avg_inference_ms, 1),
        "model_load_time_s": round(load_time, 1),
        "device": str(device),
        "box_threshold": args.box_threshold,
        "text_threshold": args.text_threshold,
        "text_prompts": text_prompts,
    }

    print("\n" + "=" * 60)
    print("EVALUATION SUMMARY")
    print("=" * 60)
    for k, v in summary.items():
        print(f"  {k}: {v}")

    # Save detailed results
    output = {"summary": summary, "per_image": results}
    metrics_path = output_dir / "eval_metrics.json"
    with open(metrics_path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"\nMetrics saved to: {metrics_path}")
    print(f"Annotated images in: {output_dir / 'annotated'}")
    print(f"Mask PNGs in: {output_dir / 'masks'}")

    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", required=True, help="Directory of test images")
    parser.add_argument("--output-dir", required=True, help="Directory for output")
    parser.add_argument(
        "--text-prompts",
        default="shoe.,running shoe.,footwear.",
        help="Comma-separated text prompts to try (best result kept)",
    )
    parser.add_argument("--box-threshold", type=float, default=0.3)
    parser.add_argument("--text-threshold", type=float, default=0.25)
    args = parser.parse_args()
    evaluate(args)


if __name__ == "__main__":
    main()
