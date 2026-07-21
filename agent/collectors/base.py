"""Base collector — all collectors inherit from this."""

import asyncio
import shutil
from abc import ABC, abstractmethod
from pathlib import Path


FACTORY_SCRIPTS_DIR = Path(__file__).parent.parent.parent / "factory-scripts"


class BaseCollector(ABC):
    """
    Abstract base for all DB collectors.

    Each collector tries two strategies in order:
      1. Run the PowerShell factory info-gather script (preferred — battle-tested)
      2. Fall back to a native Python query (no PS dependency)

    The `collect(job)` method must return a dict with at minimum:
      {
        "sourceType":   str,
        "version":      str,
        "databaseName": str,
        "host":         str,
        "collectedAt":  ISO datetime str,
        ...db-specific fields...
      }
    """

    @abstractmethod
    async def collect(self, job: dict) -> dict:
        ...

    # ── Helpers ───────────────────────────────────────────────────────────────

    async def _run_powershell(self, script_path: Path, args: list[str], timeout: int = 300) -> tuple[int, str, str]:
        """Run a PowerShell script and return (returncode, stdout, stderr)."""
        if not shutil.which("pwsh") and not shutil.which("powershell"):
            raise RuntimeError("PowerShell (pwsh) not found in PATH")
        ps_exe = "pwsh" if shutil.which("pwsh") else "powershell"
        cmd = [ps_exe, "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(script_path), *args]
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        except asyncio.TimeoutError:
            proc.kill()
            raise TimeoutError(f"PowerShell script timed out after {timeout}s")
        return proc.returncode, stdout.decode(errors="replace"), stderr.decode(errors="replace")

    @staticmethod
    def _now_iso() -> str:
        from datetime import datetime, timezone
        return datetime.now(timezone.utc).isoformat()
