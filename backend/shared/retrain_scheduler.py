"""Runs a service's retraining job on a schedule (spec §23.26).

The job runs as a separate process (`python -m <module> --auto`), so several
minutes of CPU-heavy training never slow down the requests the service is
answering. The job itself decides whether there is enough new feedback to
train and whether the result is good enough to replace the live model; the
service picks up a promoted model by itself (it watches the model card).

Run it in ONE place per deployment: either this in-service loop
(AUTO_RETRAIN_HOURS > 0 on one replica) or the same command as a Kubernetes
CronJob with AUTO_RETRAIN_HOURS=0 on the services. A lock file in the model
folder stops two runs overlapping anyway.
"""

from __future__ import annotations

import asyncio
import logging
import sys
from pathlib import Path

logger = logging.getLogger("smartfit.retrain")

FIRST_RUN_DELAY_SECONDS = 600  # let the service start and warm up first
JOB_TIMEOUT_SECONDS = 2 * 3600
BACKEND_DIR = Path(__file__).resolve().parents[1]


async def run_job(module: str, *args: str, timeout: float = JOB_TIMEOUT_SECONDS) -> int:
    proc = await asyncio.create_subprocess_exec(
        sys.executable, "-m", module, *args,
        cwd=str(BACKEND_DIR),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except TimeoutError:
        proc.kill()
        await proc.wait()
        logger.error("%s timed out after %.0f s and was stopped", module, timeout)
        return -1
    tail = (out or b"").decode("utf-8", "replace").strip().splitlines()[-5:]
    logger.info("%s finished (exit %s): %s", module, proc.returncode, " | ".join(tail))
    return proc.returncode or 0


async def retrain_loop(module: str, hours: float, first_delay: float = FIRST_RUN_DELAY_SECONDS) -> None:
    """Forever: wait, run the job, wait `hours`. Never raises (a failed run is
    logged and retried at the next interval)."""
    await asyncio.sleep(first_delay)
    while True:
        try:
            await run_job(module, "--auto")
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("retraining job %s could not run", module)
        await asyncio.sleep(max(60.0, hours * 3600))
