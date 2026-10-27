# ComfyUI + MOSS-Image — RunPod template

A RunPod pod template that boots straight into ComfyUI with the
[Comfy-Org/MOSS-Image](https://huggingface.co/Comfy-Org/MOSS-Image) models.

- ComfyUI (latest) + ComfyUI-Manager, PyTorch for CUDA 12.8
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
| Volume disk | 60 GB (≈110 GB if `DOWNLOAD_ALL=true`) |
| Volume mount path | `/workspace` |
| Expose HTTP ports | `8188` |
| Expose TCP ports | `22` |

Add environment variables as needed (all optional, defaults shown below).
For gated/rate-limited downloads add `HF_TOKEN`.

## 3. Deploy

Deploy a pod with the template. The first boot downloads ~20 GB with the defaults —
watch progress in the pod's logs. When you see `Starting ComfyUI on port 8188`,
click **Connect → HTTP 8188**.

Then load MOSS-Image in ComfyUI: `Load Diffusion Model` → `moss_image_sft_*`,
`Load CLIP` → `qwen3.5_9b_*`, `Load VAE` → `flux2-vae`. Check
**Workflow → Browse Templates** for an official MOSS-Image workflow.

## Environment variables

| Variable | Default | Options |
|---|---|---|
| `MOSS_VARIANT` | `sft` | `sft` (fine-tuned, best for prompting), `base`, `both` |
| `MOSS_PRECISION` | `bf16` | `bf16` (10.2 GB), `int8` (5.4 GB) |
| `TEXT_ENCODER` | `int8` | `bf16` (19.3 GB), `int8` (9.75 GB), `w4a8` (7.3 GB) |
| `MOSS_VAE` | `full` | `full`, `small`, `both` |
| `DOWNLOAD_ALL` | `false` | `true` downloads every file in the repo (~49 GB) |
| `SKIP_DOWNLOAD` | `false` | `true` starts ComfyUI without checking models |
| `COMFY_ARGS` | *(empty)* | Extra ComfyUI flags, e.g. `--lowvram` |

**GPU suggestions:** a 48 GB card (A6000, L40S) runs the defaults comfortably;
on 24 GB cards (RTX 4090/3090) use `MOSS_PRECISION=int8` and `TEXT_ENCODER=w4a8`.
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
