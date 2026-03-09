# Sourced by bin/txs -- not meant to be executed directly
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    # shellcheck disable=SC2034  # used by sourcing scripts
    BOLD='' DIM='' GREEN='' YELLOW='' CYAN='' RED='' RESET=''
fi
info()
{
    printf '%b %s\n' "${GREEN}>" "${RESET}$*"
}
warn()
{
    printf '%b %s\n' "${YELLOW}Warning:" "${RESET}$*" >&2
}
error()
{
    printf '%b %s\n' "${RED}Error:" "${RESET}$*" >&2
}
