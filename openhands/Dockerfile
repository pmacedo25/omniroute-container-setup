ARG OPENHANDS_VERSION=1.7
FROM docker.openhands.dev/openhands/openhands:${OPENHANDS_VERSION}

USER root

COPY omniroute_model_service.py \
  /app/openhands/app_server/config_api/default_llm_model_service.py
COPY patch_catalog.py /tmp/patch_catalog.py

RUN python /tmp/patch_catalog.py && rm -f /tmp/patch_catalog.py
