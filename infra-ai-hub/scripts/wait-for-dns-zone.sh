#!/usr/bin/env bash
###---------------------------------------------------------------------------------
# This script helps wait for the DNS zone to be fully propagated and available.
# It checks for the existence of the DNS zone in Azure and waits until it is found.
# the dns zone is created asynchronously, ny platform automation in landing zone.
###---------------------------------------------------------------------------------

set -euo pipefail

usage() {
	cat >&2 <<'EOF'
wait-for-dns-zone.sh

Waits until an Azure DNS zone exists (Private DNS Zone or Public DNS Zone).

Also supports waiting for a private endpoint to have a DNS zone group attached
(common when Azure Policy associates Private DNS Zones asynchronously).

Typical Terraform local-exec usage:
  bash -lc './infra/scripts/wait-for-dns-zone.sh \
	--zone-type private \
	--resource-group "<rg>" \
	--zone-name "privatelink.postgres.database.azure.com" \
	--timeout "10m" \
	--interval "10s"'

	bash -lc './infra/scripts/wait-for-dns-zone.sh \
		--resource-group "<rg>" \
		--private-endpoint-name "<pe-name>" \
		--timeout "10m" \
		--interval "10s"'

Required (choose one form):
  --zone-id <resourceId>
	OR
  --resource-group <rg> --zone-name <name>
	OR
	--resource-group <rg> --private-endpoint-name <name>

Options:
  --zone-type <private|public>   Default: private
	--private-endpoint-name <name> If set, waits for DNS zone group(s) on the private endpoint.
  --subscription <sub>          Optional. Passed to az commands.
  --timeout <dur>               Default: 10m (supports raw seconds or 15s/10m/1h/1d)
  --interval <dur>              Default: 10s (supports raw seconds or 15s/10m/1h/1d)
  -h, --help

Exit codes:
  0 - Zone found
  1 - Timed out waiting for zone
  2 - Invalid arguments / prerequisites missing
EOF
}

duration_to_seconds() {
	local value="$1"

	if echo "$value" | grep -Eq '^[0-9]+$'; then
		echo "$value"
		return 0
	fi

	if ! echo "$value" | grep -Eq '^[0-9]+[smhd]$'; then
		echo "Unsupported duration '$value'. Use e.g. 15s, 10m, 1h (or a raw number of seconds)." >&2
		return 1
	fi

	local num unit
	num="$(echo "$value" | sed -E 's/^([0-9]+)[smhd]$/\1/')"
	unit="$(echo "$value" | sed -E 's/^[0-9]+([smhd])$/\1/')"

	case "$unit" in
		s) echo "$num" ;;
		m) echo $((num * 60)) ;;
		h) echo $((num * 3600)) ;;
		d) echo $((num * 86400)) ;;
	esac
}

require_command() {
	local cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Required command not found: $cmd" >&2
		return 1
	fi
}

check_zone_exists() {
	local zone_id="$1"
	local zone_type="$2"
	local resource_group="$3"
	local zone_name="$4"
	local subscription="$5"

	local -a sub_args=()
	if [[ -n "$subscription" ]]; then
		sub_args+=(--subscription "$subscription")
	fi

	if [[ -n "$zone_id" ]]; then
		az resource show --ids "$zone_id" "${sub_args[@]}" --only-show-errors -o none >/dev/null 2>&1
		return $?
	fi

	case "$zone_type" in
		private)
			az network private-dns zone show \
				--resource-group "$resource_group" \
				--name "$zone_name" \
				"${sub_args[@]}" \
				--only-show-errors -o none >/dev/null 2>&1
			;;
		public)
			az network dns zone show \
				--resource-group "$resource_group" \
				--name "$zone_name" \
				"${sub_args[@]}" \
				--only-show-errors -o none >/dev/null 2>&1
			;;
		*)
			echo "Invalid --zone-type '$zone_type' (expected private|public)." >&2
			return 2
			;;
	esac
}

check_private_endpoint_zone_group_exists() {
	local resource_group="$1"
	local private_endpoint_name="$2"
	local subscription="$3"

	local -a sub_args=()
	if [[ -n "$subscription" ]]; then
		sub_args+=(--subscription "$subscription")
	fi

	local zone_group_count
	zone_group_count="$(az network private-endpoint dns-zone-group list \
		--resource-group "$resource_group" \
		--endpoint-name "$private_endpoint_name" \
		"${sub_args[@]}" \
		--query "length(@)" \
		--only-show-errors \
		-o tsv 2>/dev/null || echo 0)"

	[[ "$zone_group_count" =~ ^[0-9]+$ ]] && [[ "$zone_group_count" -gt 0 ]]
}

main() {
	local resource_group=""
	local zone_name=""
	local zone_type="private"
	local zone_id=""
	local private_endpoint_name=""
	local subscription=""
	local timeout="10m"
	local interval="10s"

	while [[ $# -gt 0 ]]; do
		case "$1" in
			-g|--resource-group)
				resource_group="${2:-}"; shift 2 ;;
			-n|--zone-name)
				zone_name="${2:-}"; shift 2 ;;
			--private-endpoint-name)
				private_endpoint_name="${2:-}"; shift 2 ;;
			--zone-type)
				zone_type="${2:-}"; shift 2 ;;
			--zone-id)
				zone_id="${2:-}"; shift 2 ;;
			--subscription)
				subscription="${2:-}"; shift 2 ;;
			-t|--timeout)
				timeout="${2:-}"; shift 2 ;;
			-i|--interval)
				interval="${2:-}"; shift 2 ;;
			-h|--help)
				usage
				return 0
				;;
			*)
				echo "Unknown argument: $1" >&2
				usage
				return 2
				;;
		esac
	done

	require_command az || { echo "Azure CLI (az) not found. Cannot poll for DNS zone." >&2; return 2; }

	if [[ -n "$private_endpoint_name" ]]; then
		if [[ -z "$resource_group" ]]; then
			echo "Missing required arguments. When using --private-endpoint-name, you must also set --resource-group." >&2
			usage
			return 2
		fi
	elif [[ -z "$zone_id" ]]; then
		case "$zone_type" in
			private|public) ;;
			*)
				echo "Invalid --zone-type '$zone_type' (expected private|public)." >&2
				return 2
				;;
		esac

		if [[ -z "$resource_group" || -z "$zone_name" ]]; then
			echo "Missing required arguments. Provide --zone-id or (--resource-group and --zone-name) or (--resource-group and --private-endpoint-name)." >&2
			usage
			return 2
		fi
	fi

	local timeout_seconds interval_seconds
	timeout_seconds="$(duration_to_seconds "$timeout")" || return 2
	interval_seconds="$(duration_to_seconds "$interval")" || return 2

	if [[ "$interval_seconds" -le 0 ]]; then
		echo "Interval must be > 0 seconds." >&2
		return 2
	fi
	if [[ "$timeout_seconds" -le 0 ]]; then
		echo "Timeout must be > 0 seconds." >&2
		return 2
	fi

	if [[ -n "$private_endpoint_name" ]]; then
		echo "Waiting for private endpoint DNS zone group(s) (rg='$resource_group', endpoint='$private_endpoint_name')..." >&2
	elif [[ -n "$zone_id" ]]; then
		echo "Waiting for DNS zone resource to exist (id='$zone_id')..." >&2
	else
		echo "Waiting for DNS zone to exist (type='$zone_type', rg='$resource_group', name='$zone_name')..." >&2
	fi
	echo "Timeout: $timeout ($timeout_seconds seconds), interval: $interval ($interval_seconds seconds)" >&2

	SECONDS=0
	while true; do
		if [[ -n "$private_endpoint_name" ]]; then
			if check_private_endpoint_zone_group_exists "$resource_group" "$private_endpoint_name" "$subscription"; then
				echo "Found private endpoint DNS zone group(s)." >&2
				return 0
			fi
		else
			if check_zone_exists "$zone_id" "$zone_type" "$resource_group" "$zone_name" "$subscription"; then
				echo "DNS zone found." >&2
				return 0
			fi
		fi

		if [[ "$SECONDS" -ge "$timeout_seconds" ]]; then
			if [[ -n "$private_endpoint_name" ]]; then
				echo "Timed out waiting for private endpoint DNS zone group(s) (rg='$resource_group', endpoint='$private_endpoint_name') after $timeout." >&2
			elif [[ -n "$zone_id" ]]; then
				echo "Timed out waiting for DNS zone (id='$zone_id') after $timeout." >&2
			else
				echo "Timed out waiting for DNS zone (type='$zone_type', rg='$resource_group', name='$zone_name') after $timeout." >&2
			fi
			return 1
		fi

		sleep "$interval_seconds"
	done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
