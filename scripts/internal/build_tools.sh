# Copyright (c) 2026 fiqys
# SPDX-License-Identifier: GPL-3.0-or-later

mkdir -p "$TOOLS_DIR/bin"

if [ ! -x "$TOOLS_DIR/bin/img2sdat" ]; then
    if [ ! -f "$SRC_DIR/external/img2sdat/img2sdat" ]; then
        LOGE "external/img2sdat is missing, run: git submodule update --init"
        return 1
    fi
    ln -sf "$SRC_DIR/external/img2sdat/img2sdat" "$TOOLS_DIR/bin/img2sdat"
fi

if [ ! -x "$TOOLS_DIR/bin/signapk" ]; then
    JAR="$(find "$SRC_DIR/external/signapk" -name "*.jar" -path "*build/libs*" 2> /dev/null | head -n 1)"
    if [ ! "$JAR" ]; then
        LOG_STEP_IN true "Building signapk..."
        (cd "$SRC_DIR/external/signapk" && ./gradlew -q shadowJar) || { LOG_STEP_OUT; return 1; }
        LOG_STEP_OUT
        JAR="$(find "$SRC_DIR/external/signapk" -name "*.jar" -path "*build/libs*" 2> /dev/null | head -n 1)"
    fi
    if [ ! "$JAR" ]; then
        LOGE "Failed to build signapk"
        return 1
    fi
    printf '#!/usr/bin/env bash\nexec java -jar "%s" "$@"\n' "$JAR" > "$TOOLS_DIR/bin/signapk"
    chmod +x "$TOOLS_DIR/bin/signapk"
fi
