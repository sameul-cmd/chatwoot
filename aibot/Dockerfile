FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY pyproject.toml ./
COPY src ./src
# Optional build secret `cabundle` = extra CA bundle for restricted networks (not used in normal builds).
RUN --mount=type=secret,id=cabundle,required=false \
    if [ -f /run/secrets/cabundle ]; then export PIP_CERT=/run/secrets/cabundle; fi && \
    pip install --no-cache-dir . && useradd --system --uid 10001 --home /data aibot && mkdir -p /data && chown aibot /data
USER aibot
EXPOSE 8000
CMD ["uvicorn", "aibot.app:app_from_env", "--factory", "--host", "0.0.0.0", "--port", "8000"]
