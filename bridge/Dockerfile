# vspin-bridge mit Simulator im Container (docker-compose.yml im Repo-Root, #21).
# BLE gibt es hier nicht: Docker Desktop reicht unter Windows kein Bluetooth durch.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY pyproject.toml README.md ./
COPY src ./src
RUN pip install . && rm -rf src
COPY profiles ./profiles

# Sessions landen in /app/sessions (Volume auf den Host-Ordner sessions/).
# Profil (VSPIN_PROFILE, relativ zu /app, z. B. profiles/sprint.toml) oder Start-Kadenz
# (VSPIN_CADENCE, rpm). `exec`: die Bridge ist PID 1 und bekommt SIGTERM/SIGINT direkt –
# sie schließt die Session dann sauber ab.
ENV VSPIN_PROFILE="" VSPIN_CADENCE=80
EXPOSE 8765
CMD ["sh", "-c", "if [ -n \"$VSPIN_PROFILE\" ]; then set -- --profile \"$VSPIN_PROFILE\"; else set -- --sim-cadence \"$VSPIN_CADENCE\"; fi; exec vspin-bridge --source sim --host 0.0.0.0 \"$@\""]
