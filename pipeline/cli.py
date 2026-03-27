from __future__ import annotations

import argparse
import sys
from pathlib import Path

from pipeline.config import load_config


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="pipeline")
    parser.add_argument("topic", type=str)
    parser.add_argument("--skip-experiment", action="store_true")
    parser.add_argument("--approve-gate", type=str)
    parser.add_argument("--decide", type=str, choices=["PROCEED", "REFINE", "PIVOT"])
    parser.add_argument("--template", type=str, default="A", choices=["A", "B", "C", "D"])
    parser.add_argument("--config", type=str)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--stage", type=str)
    parser.add_argument("--log-json", action="store_true")
    parser.add_argument("--vault-dir", type=str)
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config_path = Path(args.config) if args.config else None
    config = load_config(config_path)
    from pipeline.runner import PipelineRunner

    runner = PipelineRunner(config, args)
    sys.exit(runner.run())


if __name__ == "__main__":
    main()
