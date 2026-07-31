# Copyright (c) 2026 Salvo Giangreco
# Copyright (c) 2026 fiqys
# SPDX-License-Identifier: GPL-3.0-or-later

# [
source "$SRC_DIR/scripts/utils/install_utils.sh" || exit 1

PRIVATE_KEY_PATH="$SRC_DIR/security/aosp_testkey.pk8"
PUBLIC_KEY_PATH="$SRC_DIR/security/aosp_testkey.x509.pem"

trap 'rm -rf "$TMP_DIR"' EXIT INT

GENERATE_OP_LIST()
{
    local OP_LIST_FILE="$TMP_DIR/dynamic_partitions_op_list"

    local SUPER_GROUP_NAME
    local SUPER_GROUP_SIZE

    SUPER_GROUP_NAME="$(GET_MISC_INFO "super_partition_groups" | cut -d " " -f 1)"
    SUPER_GROUP_SIZE="$(GET_MISC_INFO "super_${SUPER_GROUP_NAME}_group_size")"

    if [ ! "$SUPER_GROUP_NAME" ] || [ ! "$SUPER_GROUP_SIZE" ]; then
        LOGE "Could not read super partition group info from META/misc_info.txt"
        exit 1
    fi

    local PARTITION_SIZE=0
    local OCCUPIED_SPACE=0
    local IMG

    {
        echo "# Remove all existing dynamic partitions and groups before applying full OTA"
        echo "remove_all_groups"
        echo "# Add group $SUPER_GROUP_NAME with maximum size $SUPER_GROUP_SIZE"
        echo "add_group $SUPER_GROUP_NAME $SUPER_GROUP_SIZE"
        for p in $PARTITIONS_LIST; do
            IMG="$TMP_DIR/IMAGES/$p.img"
            [ ! -f "$IMG" ] && IMG="$TMP_DIR/$p.img"
            if [ -f "$IMG" ]; then
                PARTITION_SIZE="$(GET_IMAGE_SIZE "$IMG")"
                echo "# Add partition $p to group $SUPER_GROUP_NAME"
                echo "add $p $SUPER_GROUP_NAME"
            fi
        done
        for p in $PARTITIONS_LIST; do
            IMG="$TMP_DIR/IMAGES/$p.img"
            [ ! -f "$IMG" ] && IMG="$TMP_DIR/$p.img"
            if [ -f "$IMG" ]; then
                PARTITION_SIZE="$(GET_IMAGE_SIZE "$IMG")"
                echo "# Grow partition $p from 0 to $PARTITION_SIZE"
                echo "resize $p $PARTITION_SIZE"
                OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
            fi
        done
    } > "$OP_LIST_FILE"

    if [ "$OCCUPIED_SPACE" -gt "$SUPER_GROUP_SIZE" ]; then
        LOGE "OS size ($OCCUPIED_SPACE) is bigger than the target group size ($SUPER_GROUP_SIZE)"
        exit 1
    fi
}

GENERATE_OTA_METADATA()
{
    local DEVICE
    local FINGERPRINT
    local TIMESTAMP
    local SECURITY_PATCH_LEVEL
    local INCREMENTAL

    DEVICE="$(GET_DEVICE)"
    FINGERPRINT="$(GET_BUILD_PROP "ro.build.fingerprint")"
    TIMESTAMP="$(GET_BUILD_PROP "ro.build.date.utc")"
    SECURITY_PATCH_LEVEL="$(GET_BUILD_PROP "ro.build.version.security_patch")"
    INCREMENTAL="$(GET_BUILD_PROP "ro.build.version.incremental")"

    mkdir -p "$TMP_DIR/META-INF/com/android"

    {
        echo "ota-required-cache=0"
        echo "ota-type=BLOCK"
        echo "post-build=$FINGERPRINT"
        echo "post-build-incremental=$INCREMENTAL"
        echo "post-security-patch-level=$SECURITY_PATCH_LEVEL"
        echo "post-timestamp=$TIMESTAMP"
        echo "pre-device=$DEVICE"
    } > "$TMP_DIR/META-INF/com/android/metadata"
}

GENERATE_UPDATER_SCRIPT()
{
    local SCRIPT_FILE="$TMP_DIR/META-INF/com/google/android/updater-script"

    local PARTITION_COUNT=0

    for p in $PARTITIONS_LIST; do
        [ -f "$TMP_DIR/$p.transfer.list" ] && PARTITION_COUNT=$((PARTITION_COUNT + 1))
    done

    {
        PRINT_ASSERTIONS || exit 1

        PRINT_HEADER || exit 1

        if $TARGET_USE_DYNAMIC_PARTITIONS; then
            echo -e "\n# --- Start patching dynamic partitions ---\n"
            echo -e "\n# Update dynamic partition metadata\n"
            echo -n 'assert(update_dynamic_partitions(package_extract_file("dynamic_partitions_op_list")'
            if [ -f "$TMP_DIR/unsparse_super_empty.img" ]; then
                echo -n ', package_extract_file("unsparse_super_empty.img")'
            fi
            echo    '));'
        fi
        for p in $PARTITIONS_LIST; do
            if [ ! -f "$TMP_DIR/$p.transfer.list" ]; then
                continue
            fi
            $TARGET_USE_DYNAMIC_PARTITIONS && echo -e "\n# Patch partition $p\n"
            echo -n 'ui_print("Patching '
            echo -n "$p image unconditionally..."
            echo    '");'
            if [[ "$p" == "system" ]]; then
                echo -n 'show_progress(0.'
                echo -n "$(bc -l <<< "9 - $PARTITION_COUNT")"
                echo    '00000, 0);'
            else
                echo    'show_progress(0.100000, 0);'
            fi
            echo -n "block_image_update("
            GET_DEVICE_FROM_MOUNTPOINT "/$p"
            echo -n ', package_extract_file("'
            echo -n "$p.transfer.list"
            echo -n '"), "'
            echo -n "$p.new.dat"
            [ -f "$TMP_DIR/$p.new.dat.br" ] && echo -n ".br"
            echo -n '", "'
            echo -n "$p.patch.dat"
            echo    '") ||'
            echo -n '  abort("'
            [[ "$p" == "system" ]] && echo -n "E1001" || echo -n "E2001"
            echo -n ": Failed to update $p image."
            echo    '");'
        done
        $TARGET_USE_DYNAMIC_PARTITIONS && echo -e "\n# --- End patching dynamic partitions ---\n"

        for b in $KERNEL_BINS; do
            if [ -f "$TMP_DIR/$b.img" ]; then
                echo -n 'ui_print("Patching '
                echo -n "$b.img img..."
                echo    '");'
                echo -n 'package_extract_file("'
                echo -n "$b.img"
                echo -n '", '
                GET_DEVICE_FROM_MOUNTPOINT "/$b"
                echo    ");"
            fi
        done

        echo    'show_progress(0.100000, 10);'
        echo    'set_progress(1.000000);'

        PRINT_SEPARATOR
        echo    'ui_print(" ");'
    } > "$SCRIPT_FILE"
}
# ]

if [ "$#" != "2" ]; then
    echo "Usage: build_full_ota_zip <target_files.zip> <output.zip>" >&2
    exit 1
fi

TARGET_ZIP="$1"
OUTPUT_FILE="$2"

if ! unzip -l "$TARGET_ZIP" | grep -q "META/misc_info.txt"; then
    LOGE "File not valid: not a target-files zip (missing META/misc_info.txt)"
    exit 1
fi

[ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/META-INF/com/google/android"
cp -a "$SRC_DIR/prebuilts/deprecated-ota/update-binary" "$TMP_DIR/META-INF/com/google/android/update-binary"

LOG "- Extracting target-files zip"
EVAL "unzip -o \"$TARGET_ZIP\" -d \"$TMP_DIR\"" || exit 1

if [ ! "$OUTPUT_FILE" ]; then
    LOG "- Determining output file name"

    TARGET_ZIP_BASENAME="$(basename "$TARGET_ZIP")"
    ROM_NAME="${TARGET_ZIP_BASENAME%%_*}"
    [ "$ROM_NAME" == "$TARGET_ZIP_BASENAME" ] && ROM_NAME="rom"

    ROM_VERSION="$(GET_BUILD_PROP "ro.lineage.build.version")"
    [ ! "$ROM_VERSION" ] && ROM_VERSION="$(GET_BUILD_PROP "ro.build.version.incremental")"

    BUILD_DATE="$(GET_BUILD_PROP "ro.build.date.utc")"
    BUILD_DATE="$(date -u -d "@$BUILD_DATE" "+%Y%m%d" 2> /dev/null)"

    DEVICE_NAME="$(GET_DEVICE)"

    _CHECK_NON_EMPTY_PARAM "ROM_VERSION" "$ROM_VERSION" || exit 1
    _CHECK_NON_EMPTY_PARAM "BUILD_DATE" "$BUILD_DATE" || exit 1
    _CHECK_NON_EMPTY_PARAM "DEVICE_NAME" "$DEVICE_NAME" || exit 1

    OUTPUT_FILE="$OUT_DIR/${ROM_NAME}-${ROM_VERSION}-${BUILD_DATE}-UNOFFICIAL-${DEVICE_NAME}.zip"
fi

PARTITIONS_LIST="$(GET_PARTITIONS_LIST)"

TARGET_USE_DYNAMIC_PARTITIONS=false
[[ "$(GET_MISC_INFO "use_dynamic_partitions")" == "true" ]] && TARGET_USE_DYNAMIC_PARTITIONS=true

if $TARGET_USE_DYNAMIC_PARTITIONS; then
    LOG "- Generating dynamic_partitions_op_list"
    GENERATE_OP_LIST
fi

for p in $PARTITIONS_LIST; do
    IMG="$TMP_DIR/IMAGES/$p.img"
    [ ! -f "$IMG" ] && IMG="$TMP_DIR/$p.img"
    if [ ! -f "$IMG" ]; then
        continue
    fi
    mv -f "$IMG" "$TMP_DIR/$p.img"

    LOG "- Converting $p.img to $p.new.dat"
    EVAL "img2sdat -o \"$TMP_DIR\" \"$TMP_DIR/$p.img\"" || exit 1
    rm -f "$TMP_DIR/$p.img"

    LOG "- Compressing $p.new.dat"
    EVAL "brotli --quality=6 --output=\"$TMP_DIR/$p.new.dat.br\" \"$TMP_DIR/$p.new.dat\"" || exit 1
    rm -f "$TMP_DIR/$p.new.dat"
done

for b in $KERNEL_BINS; do
    IMG="$TMP_DIR/IMAGES/$b.img"
    if [ -f "$IMG" ]; then
        mv -f "$IMG" "$TMP_DIR/$b.img"
    fi
done

LOG "- Generating updater-script"
GENERATE_UPDATER_SCRIPT

LOG "- Generating build_info.txt"
PRINT_BUILD_INFO > "$TMP_DIR/build_info.txt"

LOG "- Generating OTA metadata"
GENERATE_OTA_METADATA

LOG "- Creating zip"
EVAL "rm -f \"$TMP_DIR/rom.zip\"" || exit 1
EVAL "cd \"$TMP_DIR\" && 7z a -tzip -mx=0 -mmt=$(nproc) -snl $TMP_DIR/rom.zip -r *.patch.dat -ir!META-INF/com/android/* -i!*.new.dat.br" || exit 1
EVAL "cd \"$TMP_DIR\" && 7z a -tzip -mx=3 -mmt=$(nproc) -snl $TMP_DIR/rom.zip -r * -xr!META-INF/com/android/* -x!*.new.dat.br -x!*.patch.dat -x!rom.zip -x!IMAGES -x!RADIO -x!RECOVERY -x!BOOT -x!ROOT -x!SYSTEM -x!VENDOR -x!PRODUCT -x!SYSTEM_EXT -x!ODM -x!ODM_DLKM -x!VENDOR_DLKM -x!SYSTEM_DLKM -x!VENDOR_BOOT -x!INIT_BOOT -x!PREBUILT_IMAGES -x!META -x!OTA -x!INSTALL" || exit 1

LOG "- Signing zip"
EVAL "signapk -w \"$PUBLIC_KEY_PATH\" \"$PRIVATE_KEY_PATH\" \"$TMP_DIR/rom.zip\" \"$OUTPUT_FILE\"" || exit 1

LOG "Done: $OUTPUT_FILE"

exit 0
