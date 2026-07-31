# Copyright (c) 2026 Salvo Giangreco
# Copyright (c) 2026 fiqys
# SPDX-License-Identifier: GPL-3.0-or-later

# [
source "$SRC_DIR/scripts/utils/build_utils.sh" || return 1

# shellcheck disable=SC2034
DEFAULT_PARTITIONS_LIST="system vendor product system_ext odm vendor_dlkm odm_dlkm system_dlkm"
# shellcheck disable=SC2034
KERNEL_BINS="boot dtbo vendor_boot init_boot recovery"
# ]

GET_MISC_INFO()
{
    _CHECK_NON_EMPTY_PARAM "KEY" "$1" || return 1

    local KEY="$1"

    if [ ! -f "$TMP_DIR/META/misc_info.txt" ]; then
        LOGE "File not found: META/misc_info.txt (not a valid target-files zip)"
        return 1
    fi

    grep "^${KEY}=" "$TMP_DIR/META/misc_info.txt" | cut -d "=" -f 2- -s | tail -n 1
}

GET_BUILD_PROP()
{
    _CHECK_NON_EMPTY_PARAM "PROP" "$1" || return 1

    local PROP="$1"

    local FILES=()
    while IFS= read -r f; do
        FILES+=("$f")
    done < <(find "$TMP_DIR" -maxdepth 4 -iname "*build.prop" 2> /dev/null)

    for f in "${FILES[@]}"; do
        local VALUE
        VALUE="$(sed -n "s/^${PROP}=//p" "$f" | head -n 1)"
        if [ "$VALUE" ]; then
            echo -n "$VALUE"
            return 0
        fi
    done
}

GET_DEVICE()
{
    local DEVICE
    local PROP

    for PROP in "ro.product.device" "ro.product.system.device" "ro.build.product"; do
        DEVICE="$(GET_BUILD_PROP "$PROP")"
        if [ "$DEVICE" ]; then
            echo -n "$DEVICE"
            return 0
        fi
    done

    DEVICE="$(GET_MISC_INFO "target_device")"
    if [ "$DEVICE" ]; then
        echo -n "$DEVICE"
        return 0
    fi
}

GET_PARTITIONS_LIST()
{
    local LIST
    LIST="$(GET_MISC_INFO "dynamic_partition_list")"
    if [ ! "$LIST" ]; then
        LIST="$DEFAULT_PARTITIONS_LIST"
    fi
    echo -n "$LIST"
}

FIND_FSTAB()
{
    local CANDIDATES=(
        "$TMP_DIR/RECOVERY/RAMDISK/system/etc/recovery.fstab"
        "$TMP_DIR/RECOVERY/RAMDISK/etc/recovery.fstab"
        "$TMP_DIR/RECOVERY/RAMDISK/first_stage_ramdisk/system/etc/recovery.fstab"
        "$TMP_DIR/BOOT/RAMDISK/system/etc/recovery.fstab"
        "$TMP_DIR/VENDOR_BOOT/RAMDISK_FRAGMENTS/recovery/RAMDISK/system/etc/recovery.fstab"
    )

    for f in "${CANDIDATES[@]}"; do
        if [ -f "$f" ]; then
            echo -n "$f"
            return 0
        fi
    done

    local FOUND
    FOUND="$(find "$TMP_DIR" -iname "*fstab*" -path "*etc*" 2> /dev/null | head -n 1)"
    if [ "$FOUND" ]; then
        echo -n "$FOUND"
        return 0
    fi

    LOGE "Could not find a recovery fstab inside the target-files package"
    return 1
}

GET_DEVICE_FROM_MOUNTPOINT()
{
    _CHECK_NON_EMPTY_PARAM "MOUNTPOINT" "$1" || return 1

    local MOUNTPOINT="$1"

    local FSTAB_FILE
    FSTAB_FILE="$(FIND_FSTAB)" || return 1

    if $TARGET_USE_DYNAMIC_PARTITIONS && IS_VALID_PARTITION_NAME "${MOUNTPOINT/\//}"; then
        echo -n "map_partition(\"${MOUNTPOINT/\//}\")"
    else
        local DEVICE
        DEVICE="$(grep -w "$MOUNTPOINT" "$FSTAB_FILE")"
        DEVICE="$(sed "/^#/d" <<< "$DEVICE")"
        DEVICE="$(head -n 1 <<< "$DEVICE")"
        DEVICE="$(cut -f 1 <<< "$DEVICE" | cut -d " " -f 1)"

        if [ ! "$DEVICE" ]; then
            if [[ "$MOUNTPOINT" == "/system" ]]; then
                GET_DEVICE_FROM_MOUNTPOINT "/"
            else
                LOGW "No entry for \"$MOUNTPOINT\" found in target fstab"
                return 1
            fi
        else
            echo -n "\"$DEVICE\""
        fi
    fi
}

PRINT_ASSERTIONS()
{
    local DEVICE
    DEVICE="$(GET_DEVICE)"
    _CHECK_NON_EMPTY_PARAM "DEVICE" "$DEVICE" || return 1

    echo -n 'getprop("ro.product.device") == "'
    echo -n "$DEVICE"
    echo -n '" || getprop("ro.build.product") == "'
    echo -n "$DEVICE"
    echo -n '" || abort("E3004: This package is for \"'
    echo -n "$DEVICE"
    echo    '\" devices; this is a \"" + getprop("ro.product.device") + "\".");'
}

PRINT_BUILD_INFO()
{
    echo -n "device="
    GET_DEVICE; echo
    echo -n "fingerprint="
    GET_BUILD_PROP "ro.build.fingerprint"; echo
    echo -n "version="
    GET_BUILD_PROP "ro.lineage.build.version"; echo
    echo -n "incremental="
    GET_BUILD_PROP "ro.build.version.incremental"; echo
    echo -n "timestamp="
    GET_BUILD_PROP "ro.build.date.utc"; echo
    echo -n "security_patch="
    GET_BUILD_PROP "ro.build.version.security_patch"; echo
}

PRINT_HEADER()
{
    local DEVICE
    local VERSION
    local FINGERPRINT

    DEVICE="$(GET_DEVICE)"
    VERSION="$(GET_BUILD_PROP "ro.lineage.build.version")"
    [ ! "$VERSION" ] && VERSION="$(GET_BUILD_PROP "ro.build.version.incremental")"
    FINGERPRINT="$(GET_BUILD_PROP "ro.build.fingerprint")"

    echo    'ui_print(" ");'
    PRINT_SEPARATOR
    echo -n 'ui_print("'
    echo -n "LineageOS $VERSION for $DEVICE"
    echo    '");'
    PRINT_SEPARATOR
    echo -n 'ui_print("'
    echo -n "Build: $FINGERPRINT"
    echo    '");'
    PRINT_SEPARATOR
}

PRINT_SEPARATOR()
{
    echo 'ui_print("****************************************");'
}
