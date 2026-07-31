# Copyright (c) 2026 fiqys <elsifycritic@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

_GET_SRC_DIR()
{
    (cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)
}

SRC_DIR="$(_GET_SRC_DIR)"
unset -f _GET_SRC_DIR

export SRC_DIR
export OUT_DIR="$SRC_DIR/out"
export TMP_DIR="$OUT_DIR/work_dir"
export TOOLS_DIR="$OUT_DIR/tools"

[[ ":$PATH:" != *":$SRC_DIR/bin:"* ]] && export PATH="$SRC_DIR/bin:$PATH"
[[ ":$PATH:" != *":$TOOLS_DIR/bin:"* ]] && export PATH="$TOOLS_DIR/bin:$PATH"

source "$SRC_DIR/scripts/utils/log_utils.sh"

if [ -f "$SRC_DIR/.gitmodules" ] && command -v git &> /dev/null; then
    if git -C "$SRC_DIR" submodule status --recursive 2> /dev/null | grep -q "^-"; then
        LOG "- Fetching submodules"
        git -C "$SRC_DIR" submodule update --init --recursive || return 1
    fi
fi

source "$SRC_DIR/scripts/internal/build_tools.sh" || return 1

return 0
