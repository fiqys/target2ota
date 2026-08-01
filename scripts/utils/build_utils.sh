# Copyright (c) 2026 Salvo Giangreco
# Copyright (c) 2026 fiqys
# SPDX-License-Identifier: GPL-3.0-or-later

# [
source "$SRC_DIR/scripts/utils/common_utils.sh"

DEPENDENCIES=(
    "7z" "bc" "brotli" "cat" "cut" "date" "dirname" "grep" "head"
    "mkdir" "mv" "protoc" "rm" "sed" "unzip" "wc" "xxd"
)
MISSING=()
for d in "${DEPENDENCIES[@]}"; do
    if ! type "$d" &> /dev/null; then
        MISSING+=("$d")
    fi
done
if [ "${#MISSING[@]}" -ne 0 ]; then
    echo -e '\033[1;31m'"The following dependencies are missing from your system:"'\033[0;31m' >&2
    printf '%s ' "${MISSING[@]}" >&2
    echo -e '\033[0m' >&2
    return 1
fi
unset DEPENDENCIES MISSING
# ]
