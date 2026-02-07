#!/bin/bash
set -euo nounset

# Custom Domain Helper
#
# Usage: ./csr-gen.sh [options] [DOMAIN] [PRIVATE_KEY]
#
# Options:
#   -i, --interactive    Run in interactive mode
#   -h, --help           Display help message and exit

# Sorry, internal! - https://apps.nrs.gov.bc.ca/int/confluence/display/DEVGUILD/Generating+a+CSR
# https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent

# Display help
display_help() {
  echo "Usage: $0 [options] [DOMAIN] [PRIVATE_KEY]"
  echo ""
  echo "Options:"
  echo "  -i, --interactive    Run in interactive mode"
  echo "  -h, --help           Display this help message and exit"
  echo ""
  echo "Examples:"
  echo "  $0 example.com                    # Specify domain"
  echo "  $0 -i example.com                 # Specify domain with interactive mode"
  echo "  $0 example.com /path/to/key.pem   # Specify domain and key"
  exit 0
}

# Parse options
INTERACTIVE=false
DOMAIN=""
PRIVATE_KEY=""

# Process options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interactive)
      INTERACTIVE=true
      shift
      ;;
    -h|--help)
      display_help
      ;;
    *)
      # First non-option arg is DOMAIN
      if [[ -z "$DOMAIN" ]]; then
        DOMAIN="$1"
      # Second non-option arg is PRIVATE_KEY
      elif [[ -z "$PRIVATE_KEY" ]]; then
        PRIVATE_KEY="$1"
      else
        echo "Error: Too many arguments"
        display_help
      fi
      shift
      ;;
  esac
done

### Get inputs

# Vanity URL (DOMAIN)
if [[ -z "${DOMAIN}" ]]; then
  if [[ "$INTERACTIVE" = false ]]; then
    echo "Error: Domain name is required in non-interactive mode"
    display_help
    exit 1
  fi
  echo "Enter the fully qualified domain name (FQDN) name for the certificate:"
  read -r DOMAIN
fi
echo -e "\nDomain: ${DOMAIN}"

# Check if private key is provided
if [[ -n "${PRIVATE_KEY}" ]]; then
  if [[ ! -f "${PRIVATE_KEY}" ]]; then
    echo "Error: Private key file ${PRIVATE_KEY} not found"
    exit 1
  fi
# Only ask about private key in interactive mode
elif [[ "$INTERACTIVE" = true ]]; then
  echo -e "\nDo you want to use an existing private key? [y/n]"
  read -r USE_EXISTING
  if [[ "${USE_EXISTING}" =~ [Yy] ]]; then
    echo "Enter the path to the existing private key file:"
    read -r PRIVATE_KEY
    
    if [[ ! -f "${PRIVATE_KEY}" ]]; then
      echo "Error: Private key file ${PRIVATE_KEY} not found"
      exit 1
    fi
  fi
fi

# Default subject
SUBJECT="/C=CA/ST=British Columbia/L=Victoria/O=Government of the Province of British Columbia/CN=${DOMAIN}"
echo -e "\nSubject: $SUBJECT"

# Accept or create a new subject only in interactive mode
if [[ "$INTERACTIVE" = true ]]; then
  echo "Accept subject? [y/n]"
  read -r ACCEPT
  if [[ ! "${ACCEPT}" =~ [Yy] ]]; then
    echo "Subject: " && read -r SUBJECT
  fi
fi

# Generate the CSR
if [[ -n "${PRIVATE_KEY}" ]]; then
  echo -e "\nUsing existing private key: ${PRIVATE_KEY}"
  # Generate CSR using existing private key
  openssl req -new -key "${PRIVATE_KEY}" -out "${DOMAIN}.csr" -subj "${SUBJECT}"
  echo -e "CSR generated successfully using existing private key"
  echo -e "The following has been created:"
  ls -l "${DOMAIN}.csr"
else
  # Generate new key pair and CSR
  openssl req -new -newkey rsa:2048 -nodes -keyout "${DOMAIN}.key" -out "${DOMAIN}.csr" -subj "${SUBJECT}"
  echo -e "New private key and CSR generated successfully"
  echo -e "The following have been created:"
  ls -l "${DOMAIN}."{csr,key}
fi

echo ""
echo "BC Gov Natural Resources Only!  ---"
echo ""
echo "Create a JIRA issue:"
echo ""
echo "- Project: Service Desk (SD)"
echo "- Issue Type: Service Request"
echo "- Title: SSL Certificate Request for ${DOMAIN}"
echo "- Summary: SSL Certificate Request for ${DOMAIN}"
echo "- Component/s: Other - N/A - Not Applicable"
echo "- Assignee: NRIDS Infrastructure and Middle Tier WLRS:EX"
echo "- Teams Involved: Tier 3 - Infrastructure"
echo "- Description: "
echo "  Please create an SSL certificate for: ${DOMAIN}"
echo ""
echo "  iStore billing codes ---"
echo "  - Client:"
echo "  - Responsibility:"
echo "  - Service Line:"
echo "  - Project:"
echo "  - Expense Authority:"
echo "  - Financial Reporting Account:"
echo ""
echo "- Attach the newly generated CSR file only"

# Open JIRA - optional, only in interactive mode
if [[ "$INTERACTIVE" = true ]]; then
  echo -e "\nWould you like to be redirected to Natural Resources JIRA? [y/n]"
  read -r ACCEPT
  if [[ "${ACCEPT}" =~ [Yy] ]]; then
    xdg-open 'https://apps.nrs.gov.bc.ca/int/jira/secure/CreateIssue!default.jspa'
  fi
fi