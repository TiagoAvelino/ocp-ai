"""Serviço de inferência DistilBERT + regra de confiança empresarial."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Literal

import torch
import yaml
from fastapi import FastAPI, HTTPException
from prometheus_client import Counter, Histogram, Info, generate_latest
from pydantic import BaseModel, Field
from starlette.responses import PlainTextResponse
from transformers import AutoModelForSequenceClassification, AutoTokenizer

MODEL_DIR = Path(os.getenv("MODEL_DIR", "/app/model"))
THRESHOLD = float(os.getenv("DECISION_THRESHOLD", "0.80"))
MODEL_VERSION = os.getenv("MODEL_VERSION", "1.0.0")

app = FastAPI(title="Customer Intent Classifier", version=MODEL_VERSION)

PREDICTIONS = Counter("prediction_requests_total", "Total prediction requests")
ERRORS = Counter("prediction_errors_total", "Prediction errors")
LATENCY = Histogram("prediction_latency_seconds", "Prediction latency")
HUMAN_REVIEW = Counter("prediction_human_review_total", "Human review decisions")
INTENT_COUNTER = Counter("prediction_intent_total", "Predictions by intent", ["intent"])
MODEL_INFO = Info("model_version_info", "Model version metadata")

label_map: dict = {}
tokenizer = None
model = None
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


class PredictRequest(BaseModel):
    text: str = Field(..., min_length=3, max_length=2000)


class PredictResponse(BaseModel):
    text: str
    predictedIntent: str
    department: str
    confidence: float
    decision: Literal["AUTO_ROUTE", "HUMAN_REVIEW"]
    modelVersion: str


@app.on_event("startup")
def load_model() -> None:
    global label_map, tokenizer, model
    map_path = MODEL_DIR / "label-map.json"
    if map_path.exists():
        label_map = json.loads(map_path.read_text(encoding="utf-8"))
    else:
        intent_path = Path("/app/config/intent_mapping.yaml")
        if intent_path.exists():
            with intent_path.open(encoding="utf-8") as handle:
                cfg = yaml.safe_load(handle)
            label_map = {"intent_to_department": cfg["intent_to_department"]}

    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    model = AutoModelForSequenceClassification.from_pretrained(MODEL_DIR).to(device)
    model.eval()
    MODEL_INFO.info({"version": MODEL_VERSION, "threshold": str(THRESHOLD)})


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "modelVersion": MODEL_VERSION}


@app.get("/metrics")
def metrics() -> PlainTextResponse:
    return PlainTextResponse(generate_latest().decode("utf-8"))


@app.post("/predict", response_model=PredictResponse)
def predict(payload: PredictRequest) -> PredictResponse:
    PREDICTIONS.inc()
    start = time.perf_counter()
    try:
        encoded = tokenizer(
            payload.text,
            truncation=True,
            padding=True,
            max_length=128,
            return_tensors="pt",
        ).to(device)
        with torch.no_grad():
            logits = model(**encoded).logits
            probs = torch.softmax(logits, dim=-1).cpu().numpy()[0]
        pred_id = int(probs.argmax())
        confidence = float(probs.max())
        id2label = model.config.id2label
        intent = id2label[pred_id]
        department = label_map.get("intent_to_department", {}).get(intent, "unknown")
        decision = "AUTO_ROUTE" if confidence >= THRESHOLD else "HUMAN_REVIEW"
        if decision == "HUMAN_REVIEW":
            HUMAN_REVIEW.inc()
        INTENT_COUNTER.labels(intent=intent).inc()
        LATENCY.observe(time.perf_counter() - start)
        return PredictResponse(
            text=payload.text,
            predictedIntent=intent,
            department=department,
            confidence=round(confidence, 4),
            decision=decision,
            modelVersion=MODEL_VERSION,
        )
    except Exception as exc:
        ERRORS.inc()
        raise HTTPException(status_code=500, detail=str(exc)) from exc
