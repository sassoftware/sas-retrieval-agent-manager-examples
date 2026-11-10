import os
import time
import json
import base64
import requests

from upload_source_file import download_image

IMAGE_FILENAMES = [f"burton-page-{i}.png" for i in range(1, 7)]

GEMMA_BASE_URL = "http://vllm-gemma-4-e4b-it-predictor.models.svc.cluster.local/v1"
GEMMA_MODEL = "gemma-4-E4B-it"
GEMMA_API_KEY = os.environ["GEMMA_API_KEY"]

FIELDS = {
    "purpose": {"type": "string"},
    "equipment_and_systems": {"type": "array", "items": {"type": "string"}},
    "labels_and_text": {"type": "array", "items": {"type": "string"}},
    "measurements_and_ratings": {"type": "array", "items": {"type": "string"}},
    "flows_and_connections": {"type": "string"},
    "warnings_and_conditions": {"type": "array", "items": {"type": "string"}},
}

SCHEMA = {
    "type": "object",
    "properties": FIELDS,
    "required": list(FIELDS),
}

PROMPT = (
    "Analyze this engineering image. Do not guess or use outside knowledge. "
    "Preserve exact names, labels, identifiers, dates, and numerical values. "
    "Extract its purpose, equipment and systems, readable text, measurements "
    "and ratings, diagrams and connections, and warnings or anomalies. "
    "Clearly indicate anything unreadable. Return JSON matching the schema."
)


def analyze_image(filename, image_bytes, mime_type):
    image_url = f"data:{mime_type};base64,{base64.b64encode(image_bytes).decode()}"

    payload = {
        "model": GEMMA_MODEL,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": f"{filename}: {PROMPT}"},
                {"type": "image_url", "image_url": {"url": image_url}},
            ],
        }],
        "max_tokens": 1500,
        "temperature": 0.1,
        "extra_body": {
            "guided_json": SCHEMA,
            "guided_whitespace_pattern": "[\n ]*",
        },
    }

    start = time.perf_counter()

    response = requests.post(
        f"{GEMMA_BASE_URL}/chat/completions",
        headers={"Authorization": f"Bearer {GEMMA_API_KEY}"},
        json=payload,
        timeout=180,
    )
    latency = time.perf_counter() - start
    response.raise_for_status()

    raw = response.json()["choices"][0]["message"]["content"]
    analysis = json.loads(raw.strip().removeprefix("```json").removesuffix("```").strip())
    analysis["image_filename"] = filename

    return analysis, latency


def exec(client):
    results = []
    total_bytes = 0
    total_latency = 0

    for filename in IMAGE_FILENAMES:
        image_bytes, mime_type = download_image(filename)
        analysis, latency = analyze_image(filename, image_bytes, mime_type)

        results.append(analysis)
        total_bytes += len(image_bytes)
        total_latency += latency

        print(f"{filename}: {latency:.2f}s")

    output = {
        "metadata": {
            "model": GEMMA_MODEL,
            "images_processed_count": len(results),
            "combined_image_size_mb": round(total_bytes / 1048576, 2),
            "total_inference_time_seconds": round(total_latency, 2),
        },
        "per_image_analysis": results,
    }

    output_file = "/tmp/gemma-4B-6-images-per-image-analysis.json"

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    client.save_file(output_file)
    print(json.dumps(output, indent=2, ensure_ascii=False))