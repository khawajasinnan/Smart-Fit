"""Diffusion try-on inference (SFR-026) lives in modal_app.py.

IDM-VTON + the DressCode LoRA need a 24 GB GPU (spec §23.8), so inference runs
on Modal (`modal_app.TryOn.generate`), not in this CPU service. The service
(main.py) prepares the inputs (imaging.py), spawns one GPU call per view
(gpu_runner.py) and stores the results. The pipeline code itself is shared
with the LoRA training: lora/idm.py (load_components / build_pipeline /
generate).
"""
