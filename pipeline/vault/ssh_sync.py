from __future__ import annotations

import subprocess
from pathlib import Path

from pipeline.core.logging import PipelineLogger
from pipeline.models.config_schema import VaultConfig


class VaultSync:
    def __init__(self, config: VaultConfig, logger: PipelineLogger) -> None:
        self.config = config
        self.logger = logger

    def sync_file(self, local_path: Path, remote_subpath: str, slug: str) -> bool:
        remote_dir = f"{self.config.base_path}/{slug}"
        remote_target = f"{self.config.ssh_host}:{remote_dir}/{remote_subpath}"

        try:
            subprocess.run(
                ["ssh", self.config.ssh_host, f"mkdir -p {remote_dir}"],
                check=True,
                timeout=self.config.ssh_timeout,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                ["scp", str(local_path), remote_target],
                check=True,
                timeout=self.config.ssh_timeout,
                capture_output=True,
                text=True,
            )
            return True
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as exc:
            self.logger.warn(f"Vault sync failed for {local_path} -> {remote_target}: {exc}")
            return False

    def sync_files(self, files: list[tuple[Path, str]], slug: str) -> int:
        success = 0
        for local_path, remote_subpath in files:
            if self.sync_file(local_path, remote_subpath, slug):
                success += 1
        return success
