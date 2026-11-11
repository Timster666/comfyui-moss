# ComfyUI · MOSS-Image + FIBO 2.0 Edit + MiniMax H3-Image

Ready-to-use ComfyUI with three image models (Comfy-Org repacks), JupyterLab and automatic model
downloads. **The default models match ComfyUI's official workflow templates**, so you can open a
template and run it straight away.

| Model | What it does | Default download |
|---|---|---|
| **MOSS-Image** | Text-to-image, plus image edit with a LoRA | ~13 GB |
| **FIBO 2.0 Edit Turbo** | Fast image editing from text instructions | ~27 GB |
| **MiniMax H3-Image** | High-quality text-to-image and image edit | ~48 GB |

All three are on by default (~88 GB). Each one can be switched off, or swapped for other variants,
with environment variables — no rebuild needed, just restart the pod.

## What's included
- **ComfyUI** (latest at build time) + **ComfyUI-Manager**
- **Standard ComfyUI layout on the volume:** everything lives in `/workspace/ComfyUI` —
  `custom_nodes`, `models`, `input`, `output`, `user`
- **Custom nodes persist:** install nodes with ComfyUI-Manager and they're still there after a
  restart; their Python packages are reinstalled automatically on boot
- **PyTorch** for CUDA 13.0
- **JupyterLab** (no password), and new terminals open in the folder you're browsing
- Models download on first boot; files already on the volume are skipped on later boots

## Getting started
1. **GPU:** **48 GB+ VRAM** (L40S, A6000, A100, H100…) with MiniMax on. With `ENABLE_MINIMAX=false`,
   MOSS + FIBO run on a **24 GB** card (RTX 4090). Pick **64 GB+ system RAM** and set the
   **CUDA version filter to 13.0+**.
2. **Volume:** **120 GB+** with the defaults (≈60 GB with MiniMax off).
3. Watch the logs until you see `All model files present` and `Starting ComfyUI on port 8188`
   (the first boot downloads ~88 GB and takes a while).
4. **Connect → ComfyUI** (port 8188), then go to **Workflow → Browse Templates** and search for
   **MOSS-Image**, **Fibo 2.0** or **MiniMax-H3-Image**. The official templates use exactly these models.
5. **Connect → Jupyter** (port 8888) for files, terminal and uploads.

## Model switches

### MOSS-Image
| Variable | Default | Options |
|---|---|---|
| `ENABLE_MOSS` | `true` | `false` skips all MOSS-Image models |
| `MOSS_VARIANT` | `sft` | `sft` (fine-tuned), `base`, `both` (base = the "MOSS-Image Base" templates) |
| `MOSS_PRECISION` | `int8` | `int8` (5.4 GB), `bf16` (10.2 GB) |
| `MOSS_TEXT_ENCODER` | `w4a8` | `w4a8` (7.3 GB), `int8` (9.75 GB), `bf16` (19.3 GB) |
| `MOSS_VAE` | `small` | `small`, `full`, `both` |
| `MOSS_EDIT_LORA` | `true` | LoRA for the **MOSS-Image: Image Edit LoRA** template |
| `MOSS_DEPTH_CONTROL` | `false` | LoRA + MoGe depth model + int8 text encoder for **MOSS-Image: Color & Depth Control** |
| `DOWNLOAD_ALL` | `false` | `true` downloads the whole MOSS-Image repo (~49 GB) |

### FIBO 2.0 Edit
| Variable | Default | Options |
|---|---|---|
| `ENABLE_FIBO` | `true` | `false` skips all FIBO models |
| `FIBO_TURBO` | `true` | Model for **Fibo 2.0 Turbo: Image Edit** (fast, 4 steps) |
| `FIBO_DEV` | `false` | Model for **Fibo 2.0 Dev: Image Edit** |

FIBO always also downloads `qwen3vl_4b_bf16` (8.9 GB), `qwen3vl_8b_int8_convrot` (9.4 GB) and `flux2-vae`.

### MiniMax H3-Image
| Variable | Default | File | Size |
|---|---|---|---|
| `ENABLE_MINIMAX` | `true` | `false` skips all MiniMax models | |
| `MINIMAX_DIT_INT8` | `true` | `minimax_h3_image_pruned_int8_convrot` | 21.0 GB |
| `MINIMAX_DIT_W4A8` | `false` | `minimax_h3_image_pruned_w4a8` (less VRAM) | 12.5 GB |
| `MINIMAX_DIT_BF16` | `false` | `minimax_h3_image_pruned_bf16` | 40.2 GB |
| `MINIMAX_TE_INT8` | `true` | `qwen3vl_32b_minimax_h3_int8_convrot` | 27.1 GB |
| `MINIMAX_TE_NVFP4` | `false` | `qwen3vl_32b_minimax_h3_nvfp4_awq` (less VRAM) | 15.7 GB |
| `MINIMAX_PROMPT_ENHANCER` | `true` | `qwen3.5_9b_w4a8_gptq` (shared with MOSS, downloaded once) | 7.3 GB |

The MiniMax VAE (`minimax_h3_image_vae_fp16`) is always downloaded with MiniMax.
On a **32 GB RTX 5090**: `MINIMAX_DIT_INT8=false`, `MINIMAX_DIT_W4A8=true`, `MINIMAX_TE_INT8=false`,
`MINIMAX_TE_NVFP4=true`, then select those files in the workflow's loader nodes.

## Other environment variables
| Variable | Default | Options |
|---|---|---|
| `UPDATE_COMFYUI` | `false` | `true` updates ComfyUI + ComfyUI-Manager on boot |
| `INSTALL_NODE_REQS` | `true` | `false` skips reinstalling custom nodes' Python packages (faster boot) |
| `COMFY_ARGS` | — | Extra ComfyUI flags, e.g. `--lowvram` |
| `JUPYTER_PASSWORD` | — | Set to require a login for Jupyter |
| `ENABLE_JUPYTER` | `true` | `false` turns JupyterLab off |
| `SKIP_DOWNLOAD` | `false` | `true` starts ComfyUI without checking models |
| `HF_TOKEN` | — | Hugging Face token, if downloads are rate-limited |

## Ports
| Port | Service |
|---|---|
| 8188 | ComfyUI |
| 8888 | JupyterLab |
| 22 | SSH |

## Where things are saved
| Path | Contents |
|---|---|
| `/workspace/ComfyUI/models/` | Models (LoRAs in `models/loras`) |
| `/workspace/ComfyUI/custom_nodes/` | Custom nodes, kept between restarts |
| `/workspace/ComfyUI/input/` · `output/` | Uploaded / generated images |
| `/workspace/ComfyUI/user/` | Saved workflows & settings |

Use a network volume to keep everything after the pod is terminated.

## Licenses
- **MOSS-Image:** Apache 2.0
- **FIBO 2.0:** CC BY-NC 4.0 (Bria AI), **non-commercial only**
- **MiniMax H3:** MiniMax H3 Community License Agreement; check the terms before commercial use

## Links
- MOSS-Image: https://huggingface.co/Comfy-Org/MOSS-Image
- FIBO 2.0: https://huggingface.co/Comfy-Org/Fibo-2.0
- MiniMax H3-Image: https://huggingface.co/Comfy-Org/MiniMax-H3-Image
- ComfyUI: https://github.com/comfyanonymous/ComfyUI
