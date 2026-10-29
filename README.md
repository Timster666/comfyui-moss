# ComfyUI + MOSS-Image + FIBO 2.0 Edit — RunPod template

A RunPod pod template that boots straight into ComfyUI with the
[Comfy-Org/MOSS-Image](https://huggingface.co/Comfy-Org/MOSS-Image) and
[FIBO 2.0 Image Edit](https://huggingface.co/Comfy-Org/Fibo-2.0) models.

- ComfyUI (latest) + ComfyUI-Manager + JupyterLab, PyTorch for CUDA 13.0
- Models download to your **network volume** on first boot, then load instantly on later boots
- Pick model size/precision with environment variables — no rebuild needed

## 1. Build and push the image

Run this on any machine with Docker (the image has no GPU requirement to build):

```bash
docker build -t YOUR_DOCKERHUB_USER/comfyui-moss:latest .
docker push YOUR_DOCKERHUB_USER/comfyui-moss:latest
```

Building on an Apple Silicon Mac? Add `--platform linux/amd64` to the build.

## 2. Create the template in RunPod

RunPod console → **My Templates → New Template**:

| Field | Value |
|---|---|
| Template type | Pod |
| Container image | `YOUR_DOCKERHUB_USER/comfyui-moss:latest` |
| Container disk | 30 GB |
| Volume disk | 60 GB (≈100 GB if `DOWNLOAD_ALL=true`) |
| Volume mount path | `/workspace` |
| Expose HTTP ports | `8188` (ComfyUI), `8888` (JupyterLab) |
| Expose TCP ports | `22` |

Add environment variables as needed (all optional, defaults shown below).
For gated/rate-limited downloads add `HF_TOKEN`.

## 3. Deploy

Deploy a pod with the template. The first boot downloads ~40 GB with the defaults (MOSS-Image ~13 GB + FIBO 2.0 Edit ~27 GB) —
watch progress in the pod's logs. When you see `Starting ComfyUI on port 8188`,
click **Connect → HTTP 8188**.

Then load MOSS-Image in ComfyUI: `Load Diffusion Model` → `moss_image_sft_*`,
`Load CLIP` → `qwen3.5_9b_*`, `Load VAE` → `flux2-vae`. Check
**Workflow → Browse Templates** for an official MOSS-Image workflow.

## Environment variables

| Variable | Default | Options |
|---|---|---|
| `ENABLE_MOSS` | `true` | `false` skips the MOSS-Image models |
| `ENABLE_FIBO` | `true` | `false` skips the FIBO 2.0 Edit models |
| `MOSS_VARIANT` | `sft` | `sft` (fine-tuned, best for prompting), `base`, `both` |
| `MOSS_PRECISION` | `int8` | `int8` (5.4 GB), `bf16` (10.2 GB) |
| `TEXT_ENCODER` | `w4a8` | `w4a8` (7.3 GB), `int8` (9.75 GB), `bf16` (19.3 GB) |
| `MOSS_VAE` | `small` | `small`, `full`, `both` |
| `DOWNLOAD_ALL` | `false` | `true` downloads every file in the repo (~49 GB) |
| `SKIP_DOWNLOAD` | `false` | `true` starts ComfyUI without checking models |
| `COMFY_ARGS` | *(empty)* | Extra ComfyUI flags, e.g. `--lowvram` |
| `ENABLE_JUPYTER` | `true` | `false` turns JupyterLab off |
| `JUPYTER_PASSWORD` | *(empty)* | Empty = JupyterLab opens with no login. Set one if you want a login (anyone with the pod URL can otherwise open it) |

**FIBO 2.0 Edit** downloads `fibo2_edit_turbo_int8_convrot`, `qwen3vl_4b_bf16`,
`qwen3vl_8b_int8_convrot` (from Comfy-Org/Qwen3-VL) and `flux2-vae`. Its weights are
licensed **CC BY-NC 4.0 (non-commercial)** by Bria AI.

**GPU suggestions:** the defaults (int8 model, w4a8 text encoder, small VAE — matching
ComfyUI's MOSS-Image template) fit 24 GB cards like the RTX 4090/3090.
The image supports RTX 5090 / Blackwell.

## Where things live

| Path | Persists on volume |
|---|---|
| `/workspace/models/...` | ✅ models (add your own LoRAs to `/workspace/models/loras`) |
| `/workspace/ComfyUI/output` | ✅ generated images |
| `/workspace/ComfyUI/user` | ✅ saved workflows & settings |
| `/opt/ComfyUI/custom_nodes` | ❌ nodes installed via Manager are lost on pod reset — bake them into the Dockerfile to keep them |

## Updating ComfyUI

The image tracks ComfyUI `master` at build time. Rebuild and push to update, or pin a
version: `docker build --build-arg COMFYUI_REF=v0.x.y ...`
