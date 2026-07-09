FROM registry.access.redhat.com/ubi9/python-312:latest

USER root
WORKDIR /app

COPY inference/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY inference/app /app/app
COPY config/intent_mapping.yaml /app/config/intent_mapping.yaml

ENV MODEL_DIR=/app/model \
    DECISION_THRESHOLD=0.80 \
    MODEL_VERSION=1.0.0 \
    PYTHONUNBUFFERED=1

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
