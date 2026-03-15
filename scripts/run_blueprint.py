#!/usr/bin/env python3
import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a multi-agent pipeline from a YAML blueprint."
    )
    parser.add_argument("blueprint_file", help="Path to blueprint YAML file")
    parser.add_argument(
        "--var",
        action="append",
        default=[],
        help="Override variable, format key=value (repeatable)",
    )
    return parser.parse_args()


def parse_scalar(raw: str) -> Any:
    value = raw.strip()
    if value.startswith('"') and value.endswith('"') and len(value) >= 2:
        return value[1:-1]
    if value.startswith("'") and value.endswith("'") and len(value) >= 2:
        return value[1:-1]
    if value.lower() in ("null", "none", "~"):
        return None
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(part.strip()) for part in inner.split(",")]
    return value


def parse_yaml_fallback(path: Path) -> Dict[str, Any]:
    data: Dict[str, Any] = {}
    lines = path.read_text(encoding="utf-8").splitlines()
    section = None
    current_step = None

    for raw_line in lines:
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        indent = len(line) - len(line.lstrip(" "))

        if indent == 0:
            if stripped.endswith(":"):
                section = stripped[:-1]
                if section == "vars":
                    data["vars"] = {}
                elif section == "steps":
                    data["steps"] = []
                current_step = None
            elif ":" in stripped:
                key, value = stripped.split(":", 1)
                data[key.strip()] = parse_scalar(value)
                section = None
                current_step = None
            continue

        if section == "vars" and indent >= 2 and ":" in stripped:
            key, value = stripped.split(":", 1)
            data["vars"][key.strip()] = parse_scalar(value)
            continue

        if section == "steps":
            if indent == 2 and stripped.startswith("- "):
                current_step = {}
                data["steps"].append(current_step)
                inline = stripped[2:].strip()
                if inline and ":" in inline:
                    key, value = inline.split(":", 1)
                    current_step[key.strip()] = parse_scalar(value)
                continue
            if indent >= 4 and current_step is not None and ":" in stripped:
                key, value = stripped.split(":", 1)
                current_step[key.strip()] = parse_scalar(value)
                continue

    if not isinstance(data.get("steps"), list):
        raise ValueError("Invalid blueprint: missing steps list")
    return data


def load_yaml(path: Path) -> Dict[str, Any]:
    try:
        import yaml  # type: ignore

        loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not isinstance(loaded, dict):
            raise ValueError("YAML root must be a mapping")
        return loaded
    except ImportError:
        return parse_yaml_fallback(path)


def resolve_blueprint_path(raw_path: str) -> Path:
    given = Path(raw_path)
    if given.exists():
        return given.resolve()

    script_dir = Path(__file__).resolve().parent
    repo_dir = script_dir.parent

    repo_candidate = (repo_dir / raw_path).resolve()
    if repo_candidate.exists():
        return repo_candidate

    script_candidate = (script_dir / raw_path).resolve()
    if script_candidate.exists():
        return script_candidate

    raise FileNotFoundError(f"Blueprint file not found: {raw_path}")


def parse_var_overrides(pairs: List[str]) -> Dict[str, Any]:
    overrides: Dict[str, Any] = {}
    for pair in pairs:
        if "=" not in pair:
            raise ValueError(f"Invalid --var format: {pair} (expected key=value)")
        key, value = pair.split("=", 1)
        key = key.strip()
        if not key:
            raise ValueError(f"Invalid --var key in: {pair}")
        overrides[key] = parse_scalar(value)
    return overrides


def build_context(blueprint: Dict[str, Any], overrides: Dict[str, Any]) -> Dict[str, Any]:
    defaults = blueprint.get("vars") or {}
    if not isinstance(defaults, dict):
        raise ValueError("vars must be a mapping")

    context: Dict[str, Any] = dict(defaults)
    context.update(overrides)

    missing = [k for k, v in context.items() if v is None]
    if missing:
        raise ValueError(f"Missing required vars: {', '.join(missing)}")

    return context


def render_template(template: str, vars_ctx: Dict[str, Any], step_results: Dict[str, Dict[str, Any]]) -> str:
    pattern = re.compile(r"\{\{\s*([^}]+?)\s*\}\}")

    def replacer(match: re.Match[str]) -> str:
        expr = match.group(1).strip()
        if expr.startswith("steps.") and expr.endswith(".result"):
            parts = expr.split(".")
            if len(parts) != 3:
                raise KeyError(f"Invalid step expression: {expr}")
            step_id = parts[1]
            if step_id not in step_results:
                raise KeyError(f"Step result not found: {step_id}")
            return str(step_results[step_id].get("result", ""))

        if expr in vars_ctx:
            return str(vars_ctx[expr])

        raise KeyError(f"Unknown template variable: {expr}")

    return pattern.sub(replacer, template)


def normalize_depends(depends_on: Any) -> List[str]:
    if depends_on is None:
        return []
    if isinstance(depends_on, str):
        return [depends_on]
    if isinstance(depends_on, list):
        return [str(dep) for dep in depends_on]
    raise ValueError("depends_on must be string or list")


def run_step(
    orchestrate_path: Path,
    step: Dict[str, Any],
    vars_ctx: Dict[str, Any],
    step_results: Dict[str, Dict[str, Any]],
) -> Dict[str, Any]:
    step_id = str(step.get("id", "")).strip()
    agent = str(step.get("agent", "")).strip()
    task_tmpl = step.get("task")
    name_tmpl = step.get("name", step_id)

    if not step_id:
        raise ValueError("Each step must have id")
    if not agent:
        raise ValueError(f"Step '{step_id}' missing agent")
    if not isinstance(task_tmpl, str) or not task_tmpl.strip():
        raise ValueError(f"Step '{step_id}' missing task")
    if not isinstance(name_tmpl, str) or not name_tmpl.strip():
        raise ValueError(f"Step '{step_id}' missing name")

    task = render_template(task_tmpl, vars_ctx, step_results)
    name = render_template(name_tmpl, vars_ctx, step_results)

    cmd = ["bash", str(orchestrate_path), agent, task, name]
    print(f"[STEP {step_id}] START agent={agent} name={name}")
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    output = (proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")
    if proc.returncode != 0:
        print(f"[STEP {step_id}] FAIL exit={proc.returncode}")
        if output.strip():
            print(output.strip())
        raise RuntimeError(f"Step '{step_id}' failed")

    print(f"[STEP {step_id}] DONE")
    return {"result": output.strip()}


def run_blueprint(blueprint: Dict[str, Any], blueprint_path: Path, vars_ctx: Dict[str, Any]) -> None:
    steps = blueprint.get("steps")
    if not isinstance(steps, list) or not steps:
        raise ValueError("Blueprint must contain non-empty steps list")

    script_dir = Path(__file__).resolve().parent
    orchestrate_path = (script_dir / "orchestrate.sh").resolve()
    if not orchestrate_path.exists():
        raise FileNotFoundError(f"orchestrate.sh not found: {orchestrate_path}")

    print(f"[BLUEPRINT] {blueprint.get('name', blueprint_path.stem)}")
    print(f"[FILE] {blueprint_path}")

    pending: Dict[str, Dict[str, Any]] = {}
    order: List[str] = []
    for step in steps:
        if not isinstance(step, dict):
            raise ValueError("Each step must be a mapping")
        step_id = str(step.get("id", "")).strip()
        if not step_id:
            raise ValueError("Each step must have id")
        if step_id in pending:
            raise ValueError(f"Duplicate step id: {step_id}")
        pending[step_id] = step
        order.append(step_id)

    step_results: Dict[str, Dict[str, Any]] = {}
    while pending:
        progressed = False
        for step_id in order:
            if step_id not in pending:
                continue
            step = pending[step_id]
            deps = normalize_depends(step.get("depends_on"))
            if not all(dep in step_results for dep in deps):
                continue

            step_results[step_id] = run_step(orchestrate_path, step, vars_ctx, step_results)
            pending.pop(step_id)
            progressed = True

        if not progressed:
            unresolved = ", ".join(sorted(pending.keys()))
            raise RuntimeError(f"Unresolvable dependencies among steps: {unresolved}")

    print("[BLUEPRINT] COMPLETED")


def main() -> int:
    args = parse_args()
    try:
        blueprint_path = resolve_blueprint_path(args.blueprint_file)
        blueprint = load_yaml(blueprint_path)
        overrides = parse_var_overrides(args.var)
        vars_ctx = build_context(blueprint, overrides)
        run_blueprint(blueprint, blueprint_path, vars_ctx)
        return 0
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
