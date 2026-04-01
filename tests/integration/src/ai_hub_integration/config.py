from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlparse

TENANT_ENV_VAR_NAMES = {
    "wlrs-water-form-assistant": "WLRS_SUBSCRIPTION_KEY",
    "sdpr-invoice-automation": "SDPR_SUBSCRIPTION_KEY",
    "ai-hub-admin": "AI_HUB_ADMIN_SUBSCRIPTION_KEY",
    "nr-dap-fish-wildlife": "NRDAP_SUBSCRIPTION_KEY",
}

DEFAULT_OPENAI_API_VERSION = "2024-10-21"
DEFAULT_DOCINT_API_VERSION = "2024-11-30"
DEFAULT_MODEL = "gpt-4.1-mini"
OPENAI_CHAT_MODEL_PREFIXES = ("gpt-", "o1", "o3", "o4")
OPENAI_COMPATIBLE_CHAT_MODELS = {"mistral-large-3"}


def _env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def _is_openai_chat_model(model: str) -> bool:
    normalized = model.casefold()
    return normalized.startswith(OPENAI_CHAT_MODEL_PREFIXES)


def filter_chat_models(models: list[str]) -> list[str]:
    filtered: list[str] = []
    for model in models:
        normalized = model.casefold()
        if _is_openai_chat_model(model) or normalized in OPENAI_COMPATIBLE_CHAT_MODELS:
            filtered.append(model)
    return filtered


def filter_deployments_chat_models(models: list[str]) -> list[str]:
    return [model for model in models if _is_openai_chat_model(model)]


def parse_stack_output(raw_output: str) -> dict:
    start = raw_output.find("{")
    if start == -1:
        raise RuntimeError("Could not locate JSON payload in terraform output")
    return json.loads(raw_output[start:])


def _run_command(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=False)


def _extract_named_block(text: str, block_name: str) -> str:
    lines = text.splitlines()
    in_block = False
    depth = 0
    collected: list[str] = []
    block_pattern = re.compile(rf"^\s*{re.escape(block_name)}\s*=\s*\{{\s*$")

    for line in lines:
        if not in_block and block_pattern.match(line):
            in_block = True
            depth = 1
            continue

        if not in_block:
            continue

        depth += line.count("{")
        depth -= line.count("}")
        if depth <= 0:
            break
        collected.append(line)

    return "\n".join(collected)


def _derive_hostname(url: str) -> str:
    parsed = urlparse(url)
    return parsed.netloc


def _load_shared_tfvars_config(infra_dir: Path, environment: str) -> tuple[bool, str]:
    shared_tfvars = infra_dir / "params" / environment / "shared.tfvars"
    if not shared_tfvars.exists():
        return False, ""

    block = _extract_named_block(shared_tfvars.read_text(encoding="utf-8"), "app_gateway")
    enabled = bool(re.search(r"^\s*enabled\s*=\s*true\b", block, flags=re.MULTILINE))
    hostname_match = re.search(r'^\s*frontend_hostname\s*=\s*"([^"]+)"', block, flags=re.MULTILINE)
    hostname = hostname_match.group(1) if hostname_match else ""
    return enabled, hostname


def _find_bash() -> str | None:
    if os.name == "nt":
        for env_var in ("ProgramFiles", "ProgramFiles(x86)"):
            base = os.getenv(env_var)
            if not base:
                continue
            for relative_path in ("Git\\bin\\bash.exe", "Git\\usr\\bin\\bash.exe"):
                candidate = Path(base) / relative_path
                if candidate.exists():
                    return str(candidate)
    return shutil.which("bash")


def _load_stack_output_from_script(infra_dir: Path, environment: str) -> dict:
    script = infra_dir / "scripts" / "deploy-terraform.sh"
    bash = _find_bash()
    if not bash or not script.exists():
        raise RuntimeError("bash or deploy-terraform.sh is not available")

    script_path = script.relative_to(infra_dir).as_posix()
    result = _run_command([bash, script_path, "output", environment], cwd=infra_dir)
    if result.returncode != 0:
        stderr = result.stderr.strip()
        stdout = result.stdout.strip()
        raise RuntimeError(f"deploy-terraform.sh output {environment} failed\nstdout:\n{stdout}\n\nstderr:\n{stderr}")
    return parse_stack_output(result.stdout)


def _load_stack_output_direct(infra_dir: Path) -> dict:
    result = _run_command(["terraform", "output", "-json"], cwd=infra_dir)
    if result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(f"terraform output -json failed\n{stderr}")
    return json.loads(result.stdout)


@dataclass(slots=True)
class IntegrationConfig:
    environment: str
    repo_root: Path
    tests_dir: Path
    infra_dir: Path
    apim_gateway_url: str
    appgw_url: str
    appgw_deployed: bool
    appgw_config_enabled: bool
    appgw_hostname: str
    apim_name: str
    hub_keyvault_name: str
    subscription_keys: dict[str, str] = field(default_factory=dict)
    apim_keys_tenant_1: str = "ai-hub-admin"
    apim_keys_tenant_2: str = "nr-dap-fish-wildlife"
    enable_vault_key_fallback: bool = True
    openai_api_version: str = DEFAULT_OPENAI_API_VERSION
    docint_api_version: str = DEFAULT_DOCINT_API_VERSION
    default_model: str = DEFAULT_MODEL

    @classmethod
    def load(cls, environment: str | None = None) -> IntegrationConfig:
        tests_dir = Path(__file__).resolve().parents[2]
        repo_root = tests_dir.parents[1]
        infra_dir = repo_root / "infra-ai-hub"
        env = environment or os.getenv("TEST_ENV") or "test"
        appgw_config_enabled, appgw_hostname = _load_shared_tfvars_config(infra_dir, env)

        env_apim_url = os.getenv("APIM_GATEWAY_URL")
        env_keys = {tenant: os.getenv(env_name, "") for tenant, env_name in TENANT_ENV_VAR_NAMES.items()}
        if env_apim_url and any(env_keys.values()):
            appgw_url = os.getenv("APPGW_URL", env_apim_url)
            hostname = os.getenv("APPGW_HOSTNAME") or _derive_hostname(appgw_url)
            return cls(
                environment=env,
                repo_root=repo_root,
                tests_dir=tests_dir,
                infra_dir=infra_dir,
                apim_gateway_url=env_apim_url,
                appgw_url=appgw_url,
                appgw_deployed=_env_flag("APPGW_DEPLOYED", False),
                appgw_config_enabled=appgw_config_enabled,
                appgw_hostname=hostname,
                apim_name=os.getenv("APIM_NAME", ""),
                hub_keyvault_name=os.getenv("HUB_KEYVAULT_NAME", ""),
                subscription_keys=env_keys,
                apim_keys_tenant_1=os.getenv("APIM_KEYS_TENANT_1", "ai-hub-admin"),
                apim_keys_tenant_2=os.getenv("APIM_KEYS_TENANT_2", "nr-dap-fish-wildlife"),
                enable_vault_key_fallback=_env_flag("ENABLE_VAULT_KEY_FALLBACK", True),
                openai_api_version=os.getenv("OPENAI_API_VERSION", DEFAULT_OPENAI_API_VERSION),
                docint_api_version=os.getenv("DOCINT_API_VERSION", DEFAULT_DOCINT_API_VERSION),
                default_model=os.getenv("DEFAULT_MODEL", DEFAULT_MODEL),
            )

        errors: list[str] = []
        stack_output: dict | None = None
        for loader in (_load_stack_output_from_script, _load_stack_output_direct):
            try:
                stack_output = loader(infra_dir, env) if loader is _load_stack_output_from_script else loader(infra_dir)
                break
            except RuntimeError as exc:
                errors.append(str(exc))

        if stack_output is None:
            joined = "\n\n".join(errors)
            raise RuntimeError(f"Failed to load integration test configuration for {env}\n\n{joined}")

        shared_url = ((stack_output.get("appgw_url") or {}).get("value") or "").strip()
        apim_gateway_url = ((stack_output.get("apim_gateway_url") or {}).get("value") or "").strip()
        appgw_deployed = bool(shared_url)
        base_url = shared_url or apim_gateway_url
        if not base_url:
            raise RuntimeError("Neither appgw_url nor apim_gateway_url was present in terraform outputs")

        subscription_values = (stack_output.get("apim_tenant_subscriptions") or {}).get("value") or {}
        subscription_keys = {
            tenant: ((subscription_values.get(tenant) or {}).get("primary_key") or "")
            for tenant in TENANT_ENV_VAR_NAMES
        }

        hostname = appgw_hostname or _derive_hostname(base_url)

        return cls(
            environment=env,
            repo_root=repo_root,
            tests_dir=tests_dir,
            infra_dir=infra_dir,
            apim_gateway_url=base_url,
            appgw_url=shared_url,
            appgw_deployed=appgw_deployed,
            appgw_config_enabled=appgw_config_enabled,
            appgw_hostname=hostname,
            apim_name=((stack_output.get("apim_name") or {}).get("value") or "").strip(),
            hub_keyvault_name=((stack_output.get("apim_key_rotation_summary") or {}).get("value") or {}).get(
                "hub_keyvault_name", ""
            ),
            subscription_keys=subscription_keys,
            apim_keys_tenant_1=os.getenv("APIM_KEYS_TENANT_1", "ai-hub-admin"),
            apim_keys_tenant_2=os.getenv("APIM_KEYS_TENANT_2", "nr-dap-fish-wildlife"),
            enable_vault_key_fallback=_env_flag("ENABLE_VAULT_KEY_FALLBACK", True),
            openai_api_version=os.getenv("OPENAI_API_VERSION", DEFAULT_OPENAI_API_VERSION),
            docint_api_version=os.getenv("DOCINT_API_VERSION", DEFAULT_DOCINT_API_VERSION),
            default_model=os.getenv("DEFAULT_MODEL", DEFAULT_MODEL),
        )

    def get_subscription_key(self, tenant: str) -> str:
        return self.subscription_keys.get(tenant, "")

    def set_subscription_key(self, tenant: str, value: str) -> None:
        self.subscription_keys[tenant] = value
        env_var = TENANT_ENV_VAR_NAMES.get(tenant)
        if env_var:
            os.environ[env_var] = value

    def get_tenant_models(self, tenant: str) -> list[str]:
        tenant_file = self.infra_dir / "params" / self.environment / "tenants" / tenant / "tenant.tfvars"
        if not tenant_file.exists():
            return [self.default_model]

        text = tenant_file.read_text(encoding="utf-8")
        models = re.findall(r'^\s*name\s*=\s*"([^"]+)"', text, flags=re.MULTILINE)
        return models or [self.default_model]

    def get_tenant_chat_models(self, tenant: str) -> list[str]:
        return filter_chat_models(self.get_tenant_models(tenant))

    def get_tenant_deployments_chat_models(self, tenant: str) -> list[str]:
        return filter_deployments_chat_models(self.get_tenant_models(tenant))

    def is_apim_key_rotation_enabled(self) -> bool:
        shared_tfvars = self.infra_dir / "params" / self.environment / "shared.tfvars"
        if not shared_tfvars.exists():
            return True

        text = shared_tfvars.read_text(encoding="utf-8")
        apim_block = _extract_named_block(text, "apim")
        if not apim_block:
            return True

        key_rotation_block = _extract_named_block(apim_block, "key_rotation")
        if not key_rotation_block:
            return True

        match = re.search(r"^\s*rotation_enabled\s*=\s*(true|false)\b", key_rotation_block, flags=re.MULTILINE)
        if not match:
            return True
        return match.group(1).lower() != "false"


__all__ = [
    "DEFAULT_DOCINT_API_VERSION",
    "DEFAULT_MODEL",
    "DEFAULT_OPENAI_API_VERSION",
    "TENANT_ENV_VAR_NAMES",
    "IntegrationConfig",
    "filter_deployments_chat_models",
    "filter_chat_models",
    "parse_stack_output",
]
