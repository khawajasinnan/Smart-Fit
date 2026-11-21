# download_model.py – fetch the virtual‑try‑on diffusion checkpoint from Hugging Face
# ------------------------------------------------------------
# This script is placed in `backend/services/tryon/` and uses the HF token
# defined in the project `.env` (HF_TOKEN) to download the selected model
# (either `idm-vton` or `catvton`). The model name is taken from the env
# variable `TRYON_MODEL_NAME` which is set in the spec (default: idm‑vton).
# The downloaded repository is stored under `backend/services/tryon/model/`
# and can be loaded by `inference.py` via `from huggingface_hub import snapshot_download`.
# ------------------------------------------------------------
import os
from pathlib import Path

try:
    from huggingface_hub import snapshot_download
except ImportError:
    raise RuntimeError(
        "huggingface_hub not installed – run `pip install huggingface_hub` "
        "or add it to `backend/services/tryon/requirements.txt`."
    )

# ------------------------------------------------------------------
# Helper: read .env (fallback to OS env)
# ------------------------------------------------------------------
def load_env_var(key: str, default: str | None = None) -> str:
    """Return the value of *key* from the .env file or the OS environment.
    Raises a clear error if the variable is missing and no default is given.
    """
    # Fast‑path: already in the process environment (e.g., when running via `uvicorn`)
    if key in os.environ:
        return os.environ[key]

    # Load .env lazily – only the needed file is parsed.
    env_path = Path(__file__).resolve().parents[3] / ".env"
    if not env_path.is_file():
        raise FileNotFoundError(f"{env_path} not found – cannot read environment variables.")

    with env_path.open() as f:
        for line in f:
            # skip comments & empty lines
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k == key:
                return v
    if default is not None:
        return default
    raise KeyError(f"Environment variable '{key}' not found in .env or OS env.")

# ------------------------------------------------------------------
# Main download logic
# ------------------------------------------------------------------
def main() -> None:
    hf_token = load_env_var("HF_TOKEN")
    model_name = load_env_var("TRYON_MODEL_NAME", "idm-vton").lower()

    # Map the short name used in .env to the full HF repo identifier.
    repo_map = {
        "idm-vton": "yisol/IDM-VTON",
        "catvton": "zhengchong/CatVTON",
    }
    repo_id = repo_map.get(model_name)
    if repo_id is None:
        raise ValueError(
            f"Unsupported TRYON_MODEL_NAME '{model_name}'. Choose from {list(repo_map)}."
        )

    # Destination folder – keep everything inside the service directory.
    dest_dir = Path(__file__).resolve().parent / "model"
    dest_dir.mkdir(parents=True, exist_ok=True)

    print(f"Downloading {repo_id} into {dest_dir} …")
    snapshot_download(
        repo_id=repo_id,
        token=hf_token,
        local_dir=dest_dir,
        # Pull the whole repo – the checkpoint files are usually stored in the repo root.
        # `allow_patterns` can be added to restrict to *.bin, *.safetensors if desired.
        resume_download=True,
        local_dir_use_symlinks=False,
    )
    print("✅ Download complete.")

if __name__ == "__main__":
    main()
