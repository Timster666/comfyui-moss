#!/usr/bin/env bash
# Startup script for the ComfyUI + MOSS-Image RunPod template.
set -euo pipefail

WS="${WORKSPACE:-/workspace}"
MODELS="$WS/models"
REPO="Comfy-Org/MOSS-Image"

# ---- Settings (override as RunPod environment variables) --------------------
MOSS_VARIANT="${MOSS_VARIANT:-sft}"          # sft | base | both
MOSS_PRECISION="${MOSS_PRECISION:-int8}"     # int8 | bf16
TEXT_ENCODER="${TEXT_ENCODER:-w4a8}"         # w4a8 | int8 | bf16
MOSS_VAE="${MOSS_VAE:-small}"                # small | full | both
DOWNLOAD_ALL="${DOWNLOAD_ALL:-false}"        # true = grab the whole repo (~49 GB)
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-false}"
COMFY_ARGS="${COMFY_ARGS:-}"                 # extra flags, e.g. --lowvram
ENABLE_JUPYTER="${ENABLE_JUPYTER:-true}"     # JupyterLab on port 8888
JUPYTER_PASSWORD="${JUPYTER_PASSWORD:-}"     # optional login token; empty = opens with no login
# -----------------------------------------------------------------------------

# SSH (RunPod injects PUBLIC_KEY from your account settings)
if [[ -n "${PUBLIC_KEY:-}" ]]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
  ssh-keygen -A >/dev/null 2>&1 || true
  /usr/sbin/sshd || echo "[start] sshd failed to start (continuing)"
fi

# JupyterLab — started before the model download so it's usable right away
if [[ "$ENABLE_JUPYTER" == "true" ]]; then
  echo "[start] Starting JupyterLab on port 8888"
  nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
    --IdentityProvider.token="$JUPYTER_PASSWORD" --ServerApp.password='' \
    --ServerApp.allow_origin='*' --ServerApp.allow_remote_access=True \
    --ServerApp.disable_check_xsrf=True --ServerApp.root_dir="$WS" \
    > /var/log/jupyter.log 2>&1 &
fi

mkdir -p "$MODELS"/{diffusion_models,text_encoders,vae,loras,checkpoints,controlnet,upscale_models,embeddings,clip_vision} \
         "$WS/ComfyUI/output" "$WS/ComfyUI/input" "$WS/ComfyUI/user"

# ---- Build the file list ----------------------------------------------------
FILES=()
case "$MOSS_PRECISION" in
  bf16) dit_suffix="bf16" ;;
  int8) dit_suffix="int8_convrot" ;;
  *) echo "[start] Unknown MOSS_PRECISION=$MOSS_PRECISION"; exit 1 ;;
esac
case "$MOSS_VARIANT" in
  sft)  FILES+=("diffusion_models/moss_image_sft_${dit_suffix}.safetensors") ;;
  base) FILES+=("diffusion_models/moss_image_base_${dit_suffix}.safetensors") ;;
  both) FILES+=("diffusion_models/moss_image_sft_${dit_suffix}.safetensors"
                "diffusion_models/moss_image_base_${dit_suffix}.safetensors") ;;
  *) echo "[start] Unknown MOSS_VARIANT=$MOSS_VARIANT"; exit 1 ;;
esac
case "$TEXT_ENCODER" in
  bf16) FILES+=("text_encoders/qwen3.5_9b_bf16.safetensors") ;;
  int8) FILES+=("text_encoders/qwen3.5_9b_int8_convrot.safetensors") ;;
  w4a8) FILES+=("text_encoders/qwen3.5_9b_w4a8_gptq.safetensors") ;;
  *) echo "[start] Unknown TEXT_ENCODER=$TEXT_ENCODER"; exit 1 ;;
esac
case "$MOSS_VAE" in
  full)  FILES+=("vae/flux2-vae.safetensors") ;;
  small) FILES+=("vae/flux2-vae_small.safetensors") ;;
  both)  FILES+=("vae/flux2-vae.safetensors" "vae/flux2-vae_small.safetensors") ;;
  *) echo "[start] Unknown MOSS_VAE=$MOSS_VAE"; exit 1 ;;
esac

# ---- Download (skips files already on the volume) ---------------------------
wait_for_network() {
  # Pod networking can take a few seconds to come up after the container starts.
  for i in $(seq 1 60); do
    getent hosts huggingface.co >/dev/null 2>&1 && return 0
    echo "[start] Waiting for network ($i/60)..."
    sleep 2
  done
  return 1
}

missing_files() {
  local f
  for f in "${FILES[@]}"; do [[ -s "$MODELS/$f" ]] || echo "$f"; done
}

if [[ "$SKIP_DOWNLOAD" != "true" ]]; then
  export HF_HUB_DISABLE_TELEMETRY=1
  if ! wait_for_network; then
    echo "[start] !!! No network after 2 minutes — skipping model download."
  elif [[ "$DOWNLOAD_ALL" == "true" ]]; then
    echo "[start] Downloading full $REPO repo to $MODELS ..."
    for attempt in 1 2 3; do
      hf download "$REPO" --include "*.safetensors" --local-dir "$MODELS" && break
      echo "[start] Download attempt $attempt failed, retrying in 10s..."; sleep 10
    done
  else
    for attempt in 1 2 3; do
      mapfile -t TODO < <(missing_files)
      (( ${#TODO[@]} == 0 )) && break
      echo "[start] Downloading ${#TODO[@]} file(s) from $REPO (attempt $attempt) ..."
      hf download "$REPO" "${TODO[@]}" --local-dir "$MODELS" || true
    done
  fi

  # Verify — hf can report success without downloading when it's offline.
  mapfile -t STILL_MISSING < <(missing_files)
  if (( ${#STILL_MISSING[@]} )); then
    echo "[start] !!! These model files are MISSING:"
    printf '[start] !!!   %s\n' "${STILL_MISSING[@]}"
    echo "[start] !!! ComfyUI will start anyway — restart the pod to retry the download."
  else
    echo "[start] All model files present:"
    for f in "${FILES[@]}"; do echo "[start]   ✓ $f ($(du -h "$MODELS/$f" | cut -f1))"; done
  fi
fi

# ---- Launch ComfyUI ---------------------------------------------------------
cd /opt/ComfyUI
echo "[start] Starting ComfyUI on port 8188"
# shellcheck disable=SC2086
# --enable-cors-header: lets requests through RunPod's proxy (otherwise ComfyUI answers 403)
exec python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header \
  --output-directory "$WS/ComfyUI/output" \
  --input-directory  "$WS/ComfyUI/input" \
  --user-directory   "$WS/ComfyUI/user" \
  $COMFY_ARGS
