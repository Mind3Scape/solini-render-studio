import os, sys, time
from huggingface_hub import snapshot_download
root = sys.argv[1]
t = time.time()
ltx = snapshot_download("dgrauet/ltx-2.3-mlx-q4", revision="56a5866d638ecfe37c54d348e88938235185c2d4",
    local_dir=f"{root}/weights/ltx-2.3-mlx-q4", token=False,
    allow_patterns=["LICENSE", "README.md", "config.json", "embedded_config.json", "quantize_config.json", "split_model.json",
                    "connector.safetensors", "transformer-distilled-1.1.safetensors", "vae_encoder.safetensors",
                    "vae_decoder.safetensors", "spatial_upscaler_x2_v1_1.safetensors", "spatial_upscaler_x2_v1_1_config.json",
                    "audio_vae.safetensors", "vocoder.safetensors"])
print("ltx", ltx, round(time.time() - t), "s", flush=True)
g = snapshot_download("mlx-community/gemma-3-12b-it-4bit", revision="86cc6a8dedbc456dd0e4af01a9d09f396f77e558",
    local_dir=f"{root}/weights/gemma-3-12b-it-4bit", token=False)
print("gemma", g, round(time.time() - t), "s", flush=True)
