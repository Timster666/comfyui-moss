#!/usr/bin/env bash
# Startup script for the ComfyUI + MOSS-Image + FIBO 2.0 Edit RunPod template.
set -euo pipefail

WS="${WORKSPACE:-/workspace}"
MODELS="$WS/models"

# ---- Settings (override as RunPod environment variables) --------------------
ENABLE_MOSS="${ENABLE_MOSS:-true}"           # download MOSS-Image models
ENABLE_FIBO="${ENABLE_FIBO:-true}"           # download FIBO 2.0 Image Edit models
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

mkdir -p "$WS"

# JupyterLab — started before the model download so it's usable right away
if [[ "$ENABLE_JUPYTER" == "true" ]]; then
  echo "[start] Starting JupyterLab on port 8888"
  # Launched from $WS: Jupyter resolves a new terminal's folder against its own
  # working directory first, so starting it in /opt/ComfyUI sent terminals to
  # /opt/ComfyUI/models/... instead of /workspace/models/...
  (cd "$WS" && nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
    --IdentityProvider.token="$JUPYTER_PASSWORD" --ServerApp.password='' \
    --ServerApp.allow_origin='*' --ServerApp.allow_remote_access=True \
    --ServerApp.disable_check_xsrf=True --ServerApp.root_dir="$WS" \
    > /var/log/jupyter.log 2>&1 &)
fi

mkdir -p "$MODELS"/{diffusion_models,text_encoders,vae,loras,checkpoints,controlnet,upscale_models,embeddings,clip_vision} \
         "$WS/ComfyUI/output" "$WS/ComfyUI/input" "$WS/ComfyUI/user"

# Bundled workflows → ComfyUI's Workflows panel. Never overwrites a workflow
# you've edited and saved under the same name.
WF_DIR="$WS/ComfyUI/user/default/workflows"
mkdir -p "$WF_DIR"
for wf in /opt/default_workflows/*.json; do
  [[ -e "$wf" ]] || continue
  if [[ ! -e "$WF_DIR/$(basename "$wf")" ]]; then
    cp "$wf" "$WF_DIR/" && echo "[start] Added workflow: $(basename "$wf")"
  fi
done

# ---- Build the file list ----------------------------------------------------
# Each entry is "huggingface-repo|path/in/repo" — the path is also where it lands
# under /workspace/models.
MOSS_REPO="Comfy-Org/MOSS-Image"
FILES=()

if [[ "$ENABLE_MOSS" == "true" ]]; then
  case "$MOSS_PRECISION" in
    bf16) dit_suffix="bf16" ;;
    int8) dit_suffix="int8_convrot" ;;
    *) echo "[start] Unknown MOSS_PRECISION=$MOSS_PRECISION"; exit 1 ;;
  esac
  case "$MOSS_VARIANT" in
    sft)  FILES+=("$MOSS_REPO|diffusion_models/moss_image_sft_${dit_suffix}.safetensors") ;;
    base) FILES+=("$MOSS_REPO|diffusion_models/moss_image_base_${dit_suffix}.safetensors") ;;
    both) FILES+=("$MOSS_REPO|diffusion_models/moss_image_sft_${dit_suffix}.safetensors"
                  "$MOSS_REPO|diffusion_models/moss_image_base_${dit_suffix}.safetensors") ;;
    *) echo "[start] Unknown MOSS_VARIANT=$MOSS_VARIANT"; exit 1 ;;
  esac
  case "$TEXT_ENCODER" in
    bf16) FILES+=("$MOSS_REPO|text_encoders/qwen3.5_9b_bf16.safetensors") ;;
    int8) FILES+=("$MOSS_REPO|text_encoders/qwen3.5_9b_int8_convrot.safetensors") ;;
    w4a8) FILES+=("$MOSS_REPO|text_encoders/qwen3.5_9b_w4a8_gptq.safetensors") ;;
    *) echo "[start] Unknown TEXT_ENCODER=$TEXT_ENCODER"; exit 1 ;;
  esac
  case "$MOSS_VAE" in
    full)  FILES+=("$MOSS_REPO|vae/flux2-vae.safetensors") ;;
    small) FILES+=("$MOSS_REPO|vae/flux2-vae_small.safetensors") ;;
    both)  FILES+=("$MOSS_REPO|vae/flux2-vae.safetensors" "$MOSS_REPO|vae/flux2-vae_small.safetensors") ;;
    *) echo "[start] Unknown MOSS_VAE=$MOSS_VAE"; exit 1 ;;
  esac
fi

# FIBO 2.0 Image Edit (Bria AI — weights are CC BY-NC 4.0, non-commercial)
if [[ "$ENABLE_FIBO" == "true" ]]; then
  FILES+=("Comfy-Org/Fibo-2.0|diffusion_models/fibo2_edit_turbo_int8_convrot.safetensors"
          "Comfy-Org/Fibo-2.0|text_encoders/qwen3vl_4b_bf16.safetensors"
          "Comfy-Org/Qwen3-VL|text_encoders/qwen3vl_8b_int8_convrot.safetensors"
          "Comfy-Org/Fibo-2.0|vae/flux2-vae.safetensors")
fi

# Drop duplicate target paths (e.g. flux2-vae.safetensors from two repos)
declare -A SEEN=(); UNIQUE=()
for e in "${FILES[@]}"; do
  [[ -n "${SEEN[${e#*|}]:-}" ]] && continue
  SEEN[${e#*|}]=1; UNIQUE+=("$e")
done
FILES=("${UNIQUE[@]}")

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

missing_files() {   # prints the "repo|path" entries not yet on the volume
  local e
  for e in "${FILES[@]}"; do [[ -s "$MODELS/${e#*|}" ]] || echo "$e"; done
}

if [[ "$SKIP_DOWNLOAD" != "true" ]] && (( ${#FILES[@]} )); then
  export HF_HUB_DISABLE_TELEMETRY=1
  if ! wait_for_network; then
    echo "[start] !!! No network after 2 minutes — skipping model download."
  else
    if [[ "$DOWNLOAD_ALL" == "true" ]]; then
      echo "[start] Downloading full $MOSS_REPO repo to $MODELS ..."
      hf download "$MOSS_REPO" --include "*.safetensors" --local-dir "$MODELS" || true
    fi
    for attempt in 1 2 3; do
      mapfile -t TODO < <(missing_files)
      (( ${#TODO[@]} == 0 )) && break
      # one hf call per repo
      mapfile -t REPOS < <(printf '%s\n' "${TODO[@]}" | cut -d'|' -f1 | sort -u)
      for repo in "${REPOS[@]}"; do
        mapfile -t PATHS < <(printf '%s\n' "${TODO[@]}" | grep -F "$repo|" | cut -d'|' -f2)
        echo "[start] Downloading ${#PATHS[@]} file(s) from $repo (attempt $attempt) ..."
        hf download "$repo" "${PATHS[@]}" --local-dir "$MODELS" || true
      done
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
    for e in "${FILES[@]}"; do
      f="${e#*|}"; echo "[start]   ✓ $f ($(du -h "$MODELS/$f" | cut -f1))"
    done
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
