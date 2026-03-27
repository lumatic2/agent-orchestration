from __future__ import annotations

import atexit
import signal
from datetime import datetime
from pathlib import Path

from pipeline.models.pipeline_state import PipelineState, StageStatus


class TempRegistry:
    _instance: TempRegistry | None = None

    def __new__(cls) -> TempRegistry:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._paths = set()
        return cls._instance

    def register(self, path: Path) -> None:
        self._paths.add(path)

    def unregister(self, path: Path) -> None:
        self._paths.discard(path)

    def cleanup(self) -> None:
        for path in list(self._paths):
            try:
                path.unlink()
            except OSError:
                pass
            finally:
                self._paths.discard(path)


_HANDLERS_INSTALLED = False


def install_handlers(pipeline_state: PipelineState | None, pipeline_file: Path | None) -> None:
    global _HANDLERS_INSTALLED
    if _HANDLERS_INSTALLED:
        return

    registry = TempRegistry()

    def _finalize() -> None:
        registry.cleanup()
        if pipeline_state is None or pipeline_file is None:
            return
        changed = False
        now = datetime.now().isoformat(timespec="seconds")
        for stage_info in pipeline_state.stages.values():
            if stage_info.status == StageStatus.in_progress:
                stage_info.status = StageStatus.failed
                stage_info.ts = now
                changed = True
        if changed:
            pipeline_state.save(pipeline_file)

    def _handle_signal(signum: int, _frame: object) -> None:
        _finalize()
        raise SystemExit(128 + signum)

    atexit.register(_finalize)
    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)
    _HANDLERS_INSTALLED = True
