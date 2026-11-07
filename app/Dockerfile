FROM python:3.14-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

RUN groupadd --system appgroup \
    && useradd --system --gid appgroup appuser \
    && chown appuser:appgroup /app

ARG GIT_SHA=dev
ENV GIT_SHA=${GIT_SHA}

COPY --chown=appuser:appgroup app.py ./
COPY --chown=appuser:appgroup static/ ./static/

USER appuser

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
