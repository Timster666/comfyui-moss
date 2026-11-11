#!/usr/bin/env bash
# Startup script for the ComfyUI + MOSS-Image + FIBO 2.0 Edit + MiniMax H3-Image RunPod template.
# Default model choices match ComfyUI's official workflow templates (Workflow → Browse Templates).
set -euo pipefail

WS="${WORKSPACE:-/workspace}"
COMFY="$WS/ComfyUI"            # the whole ComfyUI install lives on the volume
MODELS="$COMFY/models"

# ---- Model switches (set as RunPod environment variables) -------------------
# MOSS-Image (text-to-image)
ENABLE_MOSS="${ENABLE_MOSS:-true}"
MOSS_VARIANT="${MOSS_VARIANT:-sft}"                    # sft | base | both
MOSS_PRECISION="${MOSS_PRECISION:-int8}"               # int8 | bf16
MOSS_TEXT_ENCODER="${MOSS_TEXT_ENCODER:-${TEXT_ENCODER:-w4a8}}"  # w4a8 | int8 | bf16
MOSS_VAE="${MOSS_VAE:-small}"                          # small | full | both
MOSS_EDIT_LORA="${MOSS_EDIT_LORA:-true}"               # for "MOSS-Image: Image Edit LoRA"
MOSS_DEPTH_CONTROL="${MOSS_DEPTH_CONTROL:-false}"      # for "MOSS-Image: Color & Depth Control"
DOWNLOAD_ALL="${DOWNLOAD_ALL:-false}"                  # true = whole MOSS-Image repo (~49 GB)
# FIBO 2.0 Image Edit (Bria AI — CC BY-NC 4.0, non-commercial)
ENABLE_FIBO="${ENABLE_FIBO:-true}"
FIBO_TURBO="${FIBO_TURBO:-true}"                       # for "Fibo 2.0 Turbo: Image Edit"
FIBO_DEV="${FIBO_DEV:-false}"                          # for "Fibo 2.0 Dev: Image Edit"
# MiniMax H3-Image (text-to-image + edit — needs a 48 GB+ GPU)
ENABLE_MINIMAX="${ENABLE_MINIMAX:-true}"
MINIMAX_DIT_INT8="${MINIMAX_DIT_INT8:-true}"           # 21.0 GB (official default)
MINIMAX_DIT_W4A8="${MINIMAX_DIT_W4A8:-false}"          # 12.5 GB (less VRAM)
MINIMAX_DIT_BF16="${MINIMAX_DIT_BF16:-false}"          # 40.2 GB
MINIMAX_TE_INT8="${MINIMAX_TE_INT8:-true}"             # 27.1 GB (official default)
MINIMAX_TE_NVFP4="${MINIMAX_TE_NVFP4:-false}"          # 15.7 GB (less VRAM)
MINIMAX_PROMPT_ENHANCER="${MINIMAX_PROMPT_ENHANCER:-true}"  # qwen3.5_9b_w4a8 (shared with MOSS)

# ---- Other settings ---------------------------------------------------------
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-false}"
UPDATE_COMFYUI="${UPDATE_COMFYUI:-false}"        # true = git pull ComfyUI + Manager on boot
INSTALL_NODE_REQS="${INSTALL_NODE_REQS:-true}"   # reinstall custom nodes' Python packages on boot
COMFY_ARGS="${COMFY_ARGS:-}"                     # extra flags, e.g. --lowvram
ENABLE_JUPYTER="${ENABLE_JUPYTER:-true}"         # JupyterLab on port 8888
JUPYTER_PASSWORD="${JUPYTER_PASSWORD:-}"         # optional login token; empty = opens with no login
# -----------------------------------------------------------------------------

is_on() { [[ "${1,,}" == "true" || "$1" == "1" || "${1,,}" == "yes" ]]; }

# SSH (RunPod injects PUBLIC_KEY from your account settings)
if [[ -n "${PUBLIC_KEY:-}" ]]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
  ssh-keygen -A >/dev/null 2>&1 || true
  /usr/sbin/sshd || echo "[start] sshd failed to start (continuing)"
fi

mkdir -p "$WS"

# ---- ComfyUI on the volume --------------------------------------------------
# First boot: copy the ComfyUI install from the image to /workspace/ComfyUI, the
# same layout as most ComfyUI templates (custom_nodes, models, input, output...).
# Later boots reuse it, so custom nodes and settings survive.
if [[ ! -f "$COMFY/main.py" ]]; then
  echo "[start] First boot: copying ComfyUI to $COMFY ..."
  mkdir -p "$COMFY"
  cp -an /opt/ComfyUI/. "$COMFY/"    # -n: never overwrite input/output/user already there
fi
# Earlier versions of this template kept ComfyUI's own settings file pointing at
# /workspace/models; drop it so the standard models folder is used.
rm -f "$COMFY/extra_model_paths.yaml"

# Earlier versions of this template kept models in /workspace/models — move them in.
if [[ -d "$WS/models" && ! -L "$WS/models" ]]; then
  echo "[start] Moving models from $WS/models to $MODELS ..."
  for d in "$WS/models"/*/; do
    [[ -d "$d" ]] || continue
    mkdir -p "$MODELS/$(basename "$d")"
    cp -anl "$d". "$MODELS/$(basename "$d")/" 2>/dev/null || cp -an "$d". "$MODELS/$(basename "$d")/"
  done
  rm -rf "$WS/models"
fi

# JupyterLab — started before the model download so it's usable right away.
# Launched from $WS on purpose: Jupyter resolves a new terminal's folder against
# its OWN working directory first, so starting it anywhere else sent terminals
# to the wrong folder. --ip='*' listens on IPv4 and IPv6 (RunPod's ready check).
if [[ "$ENABLE_JUPYTER" == "true" ]]; then
  echo "[start] Starting JupyterLab on port 8888"
  (cd "$WS" && nohup jupyter lab --ip='*' --port=8888 --no-browser --allow-root \
    --IdentityProvider.token="$JUPYTER_PASSWORD" --ServerApp.password='' \
    --ServerApp.allow_origin='*' --ServerApp.allow_remote_access=True \
    --ServerApp.disable_check_xsrf=True --ServerApp.root_dir="$WS" \
    > /var/log/jupyter.log 2>&1 &)
fi

mkdir -p "$MODELS"/{diffusion_models,text_encoders,vae,loras,checkpoints,controlnet,upscale_models,embeddings,clip_vision,geometry_estimation} \
         "$COMFY/output" "$COMFY/input" "$COMFY/user" "$COMFY/custom_nodes"

# ---- Optional update + Python packages --------------------------------------
if [[ "$UPDATE_COMFYUI" == "true" ]]; then
  echo "[start] Updating ComfyUI and ComfyUI-Manager ..."
  git -C "$COMFY" pull --ff-only || echo "[start] ComfyUI update failed (continuing)"
  git -C "$COMFY/custom_nodes/ComfyUI-Manager" pull --ff-only 2>/dev/null || true
fi
# Keep the image's Python packages in step with the ComfyUI version on the volume
pip install -q -r "$COMFY/requirements.txt" || echo "[start] ComfyUI requirements install failed (continuing)"
# Custom nodes' Python packages live in the image, not on the volume, so a new
# pod needs them reinstalled.
if [[ "$INSTALL_NODE_REQS" == "true" ]]; then
  for req in "$COMFY"/custom_nodes/*/requirements.txt; do
    [[ -f "$req" ]] || continue
    echo "[start] Installing packages for custom node: $(basename "$(dirname "$req")")"
    pip install -q -r "$req" || echo "[start]   failed (continuing)"
  done
fi

# Bundled workflows → ComfyUI's Workflows panel. Never overwrites a workflow
# you've edited and saved under the same name.
WF_DIR="$COMFY/user/default/workflows"
mkdir -p "$WF_DIR"
for wf in /opt/default_workflows/*.json; do
  [[ -e "$wf" ]] || continue
  if [[ ! -e "$WF_DIR/$(basename "$wf")" ]]; then
    cp "$wf" "$WF_DIR/" && echo "[start] Added workflow: $(basename "$wf")"
  fi
done

# ---- Build the file list ----------------------------------------------------
# Each entry is "huggingface-repo|path/in/repo"; the path is also where it lands
# under /workspace/ComfyUI/models. Paths match ComfyUI's official templates.
MOSS_REPO="Comfy-Org/MOSS-Image"
FILES=()

if is_on "$ENABLE_MOSS"; then
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
  case "$MOSS_TEXT_ENCODER" in
    bf16) FILES+=("$MOSS_REPO|text_encoders/qwen3.5_9b_bf16.safetensors") ;;
    int8) FILES+=("$MOSS_REPO|text_encoders/qwen3.5_9b_int8_convrot.safetensors") ;;
    w4a8) FILES+=("$MOSS_REPO|text_encoders/qwen3.5_9b_w4a8_gptq.safetensors") ;;
    *) echo "[start] Unknown MOSS_TEXT_ENCODER=$MOSS_TEXT_ENCODER"; exit 1 ;;
  esac
  case "$MOSS_VAE" in
    full)  FILES+=("$MOSS_REPO|vae/flux2-vae.safetensors") ;;
    small) FILES+=("$MOSS_REPO|vae/flux2-vae_small.safetensors") ;;
    both)  FILES+=("$MOSS_REPO|vae/flux2-vae.safetensors" "$MOSS_REPO|vae/flux2-vae_small.safetensors") ;;
    *) echo "[start] Unknown MOSS_VAE=$MOSS_VAE"; exit 1 ;;
  esac
  is_on "$MOSS_EDIT_LORA" && FILES+=("$MOSS_REPO|loras/moss_image_edit_lora_rank_64_bf16.safetensors")
  if is_on "$MOSS_DEPTH_CONTROL"; then
    FILES+=("$MOSS_REPO|loras/moss_image_color_depth_control.safetensors"
            "$MOSS_REPO|text_encoders/qwen3.5_9b_int8_convrot.safetensors"
            "Comfy-Org/MoGe|geometry_estimation/moge_3_vitg_fp16.safetensors")
  fi
fi

if is_on "$ENABLE_FIBO"; then
  is_on "$FIBO_TURBO" && FILES+=("Comfy-Org/Fibo-2.0|diffusion_models/fibo2_edit_turbo_int8_convrot.safetensors")
  is_on "$FIBO_DEV"   && FILES+=("Comfy-Org/Fibo-2.0|diffusion_models/fibo2_dev_int8_convrot.safetensors")
  FILES+=("Comfy-Org/Fibo-2.0|text_encoders/qwen3vl_4b_bf16.safetensors"
          "Comfy-Org/Qwen3-VL|text_encoders/qwen3vl_8b_int8_convrot.safetensors"
          "Comfy-Org/Fibo-2.0|vae/flux2-vae.safetensors")
fi

if is_on "$ENABLE_MINIMAX"; then
  is_on "$MINIMAX_DIT_INT8" && FILES+=("Comfy-Org/MiniMax-H3-Image|diffusion_models/minimax_h3_image_pruned_int8_convrot.safetensors")
  is_on "$MINIMAX_DIT_W4A8" && FILES+=("Comfy-Org/MiniMax-H3-Image|diffusion_models/minimax_h3_image_pruned_w4a8.safetensors")
  is_on "$MINIMAX_DIT_BF16" && FILES+=("Comfy-Org/MiniMax-H3-Image|diffusion_models/minimax_h3_image_pruned_bf16.safetensors")
  is_on "$MINIMAX_TE_INT8"  && FILES+=("Comfy-Org/MiniMax-H3|text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors")
  is_on "$MINIMAX_TE_NVFP4" && FILES+=("Comfy-Org/MiniMax-H3|text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors")
  is_on "$MINIMAX_PROMPT_ENHANCER" && FILES+=("Comfy-Org/Qwen3.5|text_encoders/qwen3.5_9b_w4a8_gptq.safetensors")
  FILES+=("Comfy-Org/MiniMax-H3-Image|vae/minimax_h3_image_vae_fp16.safetensors")
  is_on "$MINIMAX_DIT_INT8" || is_on "$MINIMAX_DIT_W4A8" || is_on "$MINIMAX_DIT_BF16" || \
    echo "[start] !!! MiniMax is on but no MiniMax diffusion model is selected."
  is_on "$MINIMAX_TE_INT8" || is_on "$MINIMAX_TE_NVFP4" || \
    echo "[start] !!! MiniMax is on but no MiniMax text encoder is selected."
fi

# Drop duplicate target paths (e.g. qwen3.5_9b_w4a8 shared by MOSS and MiniMax)
declare -A SEEN=(); UNIQUE=()
for e in ${FILES[@]+"${FILES[@]}"}; do
  [[ -n "${SEEN[${e#*|}]:-}" ]] && continue
  SEEN[${e#*|}]=1; UNIQUE+=("$e")
done
FILES=(${UNIQUE[@]+"${UNIQUE[@]}"})

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
  for e in ${FILES[@]+"${FILES[@]}"}; do [[ -s "$MODELS/${e#*|}" ]] || echo "$e"; done
}

if [[ "$SKIP_DOWNLOAD" != "true" ]] && (( ${#FILES[@]} )); then
  export HF_HUB_DISABLE_TELEMETRY=1
  if ! wait_for_network; then
    echo "[start] !!! No network after 2 minutes — skipping model download."
  else
    if is_on "$DOWNLOAD_ALL" && is_on "$ENABLE_MOSS"; then
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
cd "$COMFY"
echo "[start] Starting ComfyUI on port 8188 from $COMFY"
# --enable-cors-header: lets requests through RunPod's proxy (otherwise ComfyUI answers 403)
# shellcheck disable=SC2086
exec python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header $COMFY_ARGS
