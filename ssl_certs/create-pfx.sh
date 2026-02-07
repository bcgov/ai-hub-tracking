#!/bin/bash
set -euo pipefail

# Create PFX Bundle from PEM Certificate Files
#
# Combines a server certificate, CA chain PEM files, and a private key into a
# PFX (PKCS#12) file. Optionally creates a passwordless PFX for Key Vault import.
#
# Usage:
#   ./create-pfx.sh [options]
#   ./create-pfx.sh --cert-dir prod/aihub.gov.bc.ca --key /path/to/private.key
#   ./create-pfx.sh -i                          # Interactive mode
#
# Options:
#   -i, --interactive       Run in interactive mode (prompt for all inputs)
#   -d, --cert-dir DIR      Directory containing PEM files (required)
#   -k, --key FILE          Path to private key file (required)
#   -o, --output FILE       Output PFX filename (default: {domain}.pfx in cert-dir)
#   --passwordless          Create passwordless PFX for Key Vault (default: true)
#   --with-password         Prompt for an export password instead of passwordless
#   --verify-only           Only verify existing PFX, don't create
#   --dry-run               Show what would be done without making changes
#   -h, --help              Display help and exit
#
# Expected PEM files in cert-dir:
#   1. {domain}.pem                                  — Server certificate (leaf)
#   2. Entrust OV TLS Issuing RSA CA 2.pem           — Issuing CA
#   3. USERTrust RSA Certification Authority.pem      — Intermediate CA
#   4. Sectigo Public Server Authentication Root R46.pem — Root CA

# ─── Defaults ────────────────────────────────────────────────────────────────
INTERACTIVE=false
CERT_DIR=""
KEY_FILE=""
OUTPUT_FILE=""
PASSWORDLESS=true
VERIFY_ONLY=false
DRY_RUN=false

# ─── Chain files in order (issuing → intermediate → root) ───────────────────
CHAIN_FILES=(
  "Entrust OV TLS Issuing RSA CA 2.pem"
  "USERTrust RSA Certification Authority.pem"
  "Sectigo Public Server Authentication Root R46.pem"
)

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Help ────────────────────────────────────────────────────────────────────
display_help() {
  sed -n '3,30p' "$0" | sed 's/^# \?//'
  exit 0
}

# ─── Verify PFX helper ──────────────────────────────────────────────────────
verify_pfx() {
  local pfx_file="$1"
  local pass_arg="$2"

  echo ""
  info "Verifying PFX: $pfx_file"
  echo "───────────────────────────────────────────────────"

  # Check PFX is readable
  # -legacy required: PFX is created with -legacy for App Gateway compatibility,
  # so OpenSSL 3.x needs the legacy provider to read it.
  if ! openssl pkcs12 -in "$pfx_file" -legacy -info -nokeys -passin "$pass_arg" >/dev/null 2>&1; then
    err "Cannot read PFX file."
    return 1
  fi
  ok "PFX file is readable."

  # Extract and show leaf certificate details
  local leaf_info
  leaf_info=$(openssl pkcs12 -in "$pfx_file" -legacy -clcerts -nokeys -passin "$pass_arg" 2>/dev/null | \
    openssl x509 -noout -subject -issuer -dates -fingerprint 2>/dev/null) || true

  if [[ -n "$leaf_info" ]]; then
    info "Leaf certificate:"
    echo "$leaf_info" | sed 's/^/       /'
  fi

  # Check private key is present
  if openssl pkcs12 -in "$pfx_file" -legacy -nocerts -nodes -passin "$pass_arg" 2>/dev/null | \
    grep -q "PRIVATE KEY"; then
    ok "Private key is present."
  else
    warn "Private key may not be included."
  fi

  # Count CA certs in chain
  local ca_count
  ca_count=$(openssl pkcs12 -in "$pfx_file" -legacy -cacerts -nokeys -passin "$pass_arg" 2>/dev/null | \
    grep -c "BEGIN CERTIFICATE" 2>/dev/null || echo "0")
  info "CA certificates in chain: $ca_count"

  if [[ "$ca_count" -lt 3 ]]; then
    warn "Expected 3 CA certificates (issuing + intermediate + root). Got $ca_count."
  else
    ok "Full chain included (3 CA certificates)."
  fi

  # Verify leaf key matches cert
  local cert_modulus key_modulus
  cert_modulus=$(openssl pkcs12 -in "$pfx_file" -legacy -clcerts -nokeys -passin "$pass_arg" 2>/dev/null | \
    openssl x509 -noout -modulus 2>/dev/null | md5sum | awk '{print $1}') || true
  key_modulus=$(openssl pkcs12 -in "$pfx_file" -legacy -nocerts -nodes -passin "$pass_arg" 2>/dev/null | \
    openssl rsa -noout -modulus 2>/dev/null | md5sum | awk '{print $1}') || true

  if [[ -n "$cert_modulus" && "$cert_modulus" == "$key_modulus" ]]; then
    ok "Private key matches certificate."
  elif [[ -n "$cert_modulus" ]]; then
    err "Private key does NOT match certificate!"
    return 1
  fi

  echo "───────────────────────────────────────────────────"
  ok "PFX verification passed."
  return 0
}

# ─── Parse arguments ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interactive)   INTERACTIVE=true; shift ;;
    -d|--cert-dir)      CERT_DIR="$2"; shift 2 ;;
    -k|--key)           KEY_FILE="$2"; shift 2 ;;
    -o|--output)        OUTPUT_FILE="$2"; shift 2 ;;
    --passwordless)     PASSWORDLESS=true; shift ;;
    --with-password)    PASSWORDLESS=false; shift ;;
    --verify-only)      VERIFY_ONLY=true; shift ;;
    --dry-run)          DRY_RUN=true; shift ;;
    -h|--help)          display_help ;;
    *)                  err "Unknown option: $1"; display_help ;;
  esac
done

# ─── Verify-only mode ───────────────────────────────────────────────────────
if [[ "$VERIFY_ONLY" == true ]]; then
  if [[ -z "$OUTPUT_FILE" ]]; then
    if [[ "$INTERACTIVE" == true ]]; then
      echo -e "\nEnter the path to the PFX file to verify:"
      read -r OUTPUT_FILE
    else
      err "Specify the PFX file with --output or -i for interactive."
      exit 1
    fi
  fi
  if [[ ! -f "$OUTPUT_FILE" ]]; then
    err "PFX file not found: $OUTPUT_FILE"
    exit 1
  fi

  echo -e "\nIs the PFX passwordless? [Y/n]"
  read -r ANSWER
  if [[ "$ANSWER" =~ ^[Nn] ]]; then
    echo "Enter the PFX password:"
    read -rs PFX_PASS
    verify_pfx "$OUTPUT_FILE" "pass:${PFX_PASS}"
  else
    verify_pfx "$OUTPUT_FILE" "pass:"
  fi
  exit $?
fi

# ─── Gather inputs ──────────────────────────────────────────────────────────

# Certificate directory
if [[ -z "$CERT_DIR" ]]; then
  if [[ "$INTERACTIVE" == false ]]; then
    err "Certificate directory is required. Use --cert-dir DIR or -i for interactive."
    exit 1
  fi
  echo -e "\nEnter the directory containing PEM certificate files:"
  echo "  (e.g., prod/aihub.gov.bc.ca)"
  read -r CERT_DIR
fi

# Resolve to absolute if relative
CERT_DIR=$(cd "$(dirname "$0")" && cd "$(dirname "$CERT_DIR")" && pwd)/$(basename "$CERT_DIR")

if [[ ! -d "$CERT_DIR" ]]; then
  err "Directory not found: $CERT_DIR"
  exit 1
fi

# Auto-detect domain from .pem server cert (exclude known CA files)
DOMAIN=""
for pem in "$CERT_DIR"/*.pem; do
  basename_pem=$(basename "$pem")
  # Skip known CA chain files
  skip=false
  for chain_file in "${CHAIN_FILES[@]}"; do
    [[ "$basename_pem" == "$chain_file" ]] && skip=true && break
  done
  [[ "$skip" == true ]] && continue
  # Skip chain file we may have created
  [[ "$basename_pem" == "ca-chain.pem" ]] && continue
  # This should be the server cert
  DOMAIN="${basename_pem%.pem}"
  break
done

if [[ -z "$DOMAIN" ]]; then
  err "Could not find a server certificate PEM in $CERT_DIR"
  err "Expected: {domain}.pem (e.g., aihub.gov.bc.ca.pem)"
  exit 1
fi

SERVER_CERT="$CERT_DIR/${DOMAIN}.pem"
info "Detected domain: $DOMAIN"
info "Server cert: $SERVER_CERT"

# Validate all chain files exist
for chain_file in "${CHAIN_FILES[@]}"; do
  if [[ ! -f "$CERT_DIR/$chain_file" ]]; then
    err "Missing CA chain file: $CERT_DIR/$chain_file"
    exit 1
  fi
done
ok "All CA chain files found."

# Private key
if [[ -z "$KEY_FILE" ]]; then
  if [[ "$INTERACTIVE" == false ]]; then
    err "Private key is required. Use --key FILE or -i for interactive."
    exit 1
  fi
  echo -e "\nEnter the path to the private key file:"
  read -r KEY_FILE
fi

if [[ ! -f "$KEY_FILE" ]]; then
  err "Private key file not found: $KEY_FILE"
  exit 1
fi

# Verify key is valid
if ! openssl rsa -in "$KEY_FILE" -check -noout >/dev/null 2>&1; then
  # Try EC key
  if ! openssl ec -in "$KEY_FILE" -check -noout >/dev/null 2>&1; then
    err "Invalid private key: $KEY_FILE"
    exit 1
  fi
fi
ok "Private key is valid."

# Verify key matches server cert (key-type agnostic check)
CERT_PUB_HASH=$(openssl x509 -in "$SERVER_CERT" -noout -pubkey 2>/dev/null \
  | openssl pkey -pubin -outform pem 2>/dev/null \
  | md5sum | awk '{print $1}') || true
KEY_PUB_HASH=$(openssl pkey -in "$KEY_FILE" -pubout -outform pem 2>/dev/null \
  | md5sum | awk '{print $1}') || true

if [[ -n "$CERT_PUB_HASH" && -n "$KEY_PUB_HASH" ]]; then
  if [[ "$CERT_PUB_HASH" != "$KEY_PUB_HASH" ]]; then
    err "Private key does NOT match server certificate (public keys differ)!"
    err "  Cert public key hash: $CERT_PUB_HASH"
    err "  Key public key hash:  $KEY_PUB_HASH"
    exit 1
  fi
else
  # Fallback: RSA modulus comparison (for environments without 'openssl pkey')
  CERT_MOD=$(openssl x509 -in "$SERVER_CERT" -noout -modulus 2>/dev/null | md5sum | awk '{print $1}') || true
  KEY_MOD=$(openssl rsa -in "$KEY_FILE" -noout -modulus 2>/dev/null | md5sum | awk '{print $1}') || true
  if [[ -n "$CERT_MOD" && -n "$KEY_MOD" && "$CERT_MOD" != "$KEY_MOD" ]]; then
    err "Private key does NOT match server certificate!"
    err "  Cert modulus hash: $CERT_MOD"
    err "  Key modulus hash:  $KEY_MOD"
    exit 1
  fi
fi
ok "Private key matches server certificate."

# Output file
if [[ -z "$OUTPUT_FILE" ]]; then
  if [[ "$PASSWORDLESS" == true ]]; then
    OUTPUT_FILE="$CERT_DIR/${DOMAIN}.pfx"
  else
    OUTPUT_FILE="$CERT_DIR/${DOMAIN}.pfx"
  fi
fi

# Password mode
if [[ "$INTERACTIVE" == true && "$PASSWORDLESS" == true ]]; then
  echo -e "\nCreate passwordless PFX (for Key Vault import)? [Y/n]"
  read -r ANSWER
  [[ "$ANSWER" =~ ^[Nn] ]] && PASSWORDLESS=false
fi

EXPORT_PASSWORD=""
if [[ "$PASSWORDLESS" == false ]]; then
  echo -e "\nEnter export password for the PFX:"
  read -rs EXPORT_PASSWORD
  echo ""
  echo "Confirm password:"
  read -rs EXPORT_CONFIRM
  echo ""
  if [[ "$EXPORT_PASSWORD" != "$EXPORT_CONFIRM" ]]; then
    err "Passwords do not match."
    exit 1
  fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Create PFX from PEM Files"
echo "═══════════════════════════════════════════════════════════"
info "Domain:       $DOMAIN"
info "Server cert:  $SERVER_CERT"
info "Chain files:"
for f in "${CHAIN_FILES[@]}"; do
  info "              $f"
done
info "Private key:  $KEY_FILE"
info "Output:       $OUTPUT_FILE"
info "Passwordless: $PASSWORDLESS"
info "Dry Run:      $DRY_RUN"
echo "═══════════════════════════════════════════════════════════"

if [[ "$INTERACTIVE" == true ]]; then
  echo -e "\nProceed? [y/N]"
  read -r CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    warn "Aborted."
    exit 0
  fi
fi

# ─── Build CA chain ─────────────────────────────────────────────────────────
CHAIN_FILE="$CERT_DIR/ca-chain.pem"

if [[ "$DRY_RUN" == true ]]; then
  warn "[DRY RUN] Would create CA chain: $CHAIN_FILE"
  warn "[DRY RUN] Would create PFX: $OUTPUT_FILE"
else
  info "Building CA chain file..."
  : > "$CHAIN_FILE"
  for f in "${CHAIN_FILES[@]}"; do
    cat "$CERT_DIR/$f" >> "$CHAIN_FILE"
    # Ensure newline between certs
    echo "" >> "$CHAIN_FILE"
  done
  ok "CA chain created: $CHAIN_FILE"

  # ─── Create PFX ─────────────────────────────────────────────────────────
  info "Creating PFX bundle..."

  if [[ -f "$OUTPUT_FILE" ]]; then
    warn "Output file exists — backing up to ${OUTPUT_FILE}.bak"
    cp "$OUTPUT_FILE" "${OUTPUT_FILE}.bak"
  fi

  # CRITICAL: -legacy flag required for OpenSSL 3.x compatibility with Azure App Gateway.
  # Without it, OpenSSL 3.x uses AES-256-CBC encryption which App GW cannot parse
  # (cert shows dashes for all fields in the portal).
  openssl pkcs12 -export -legacy \
    -out "$OUTPUT_FILE" \
    -inkey "$KEY_FILE" \
    -in "$SERVER_CERT" \
    -certfile "$CHAIN_FILE" \
    -name "$DOMAIN" \
    -passout "pass:${EXPORT_PASSWORD}"

  ok "PFX created: $OUTPUT_FILE"

  # ─── Verify ────────────────────────────────────────────────────────────
  verify_pfx "$OUTPUT_FILE" "pass:${EXPORT_PASSWORD}"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
ok "PFX bundle created successfully!"
echo "═══════════════════════════════════════════════════════════"
echo ""
info "Output: $OUTPUT_FILE"
info "Size:   $(du -h "$OUTPUT_FILE" 2>/dev/null | awk '{print $1}' || echo 'N/A')"
echo ""
if [[ "$PASSWORDLESS" == true ]]; then
  info "This is a passwordless PFX — ready for Key Vault import:"
  info "  ./upload-cert-keyvault.sh --env {env} --pfx \"$OUTPUT_FILE\" --vault-name {kv}"
else
  info "This PFX has a password — use for direct App Gateway upload:"
  info "  ./upload-cert-direct.sh --env {env} --pfx \"$OUTPUT_FILE\" --password SECRET"
fi
