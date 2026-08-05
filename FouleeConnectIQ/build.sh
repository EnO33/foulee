#!/usr/bin/env bash
#
# Build the Foulée Connect IQ app locally.
#
# This script is the real gate for the Monkey C code: the Connect IQ SDK cannot
# be installed on a GitHub runner without a Garmin account, so CI only runs
# `./build.sh validate` (which needs no SDK). Everything else — the actual
# compile across the device matrix — runs here, on a machine that has the SDK.
# Run `./build.sh build` before pushing anything that touches FouleeConnectIQ/.
# See README.md, section « Intégration continue ».
#
#   ./build.sh validate           static checks, no SDK needed (what CI runs)
#   ./build.sh build [device…]    compile every device in the manifest
#   ./build.sh test [device]      compile the unit-test build (default: venu2)
#   ./build.sh package            build the .iq bundle for the store
#
# Overridable:
#   CIQ_SDK_HOME          SDK root (default: the SDK Manager's current SDK)
#   CIQ_DEVELOPER_KEY     .der private key (default: $HOME/.garmin/foulee_developer_key.der)
#   JAVA_HOME             JDK to run monkeyc with

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Absolute, because `usage` reads this file back after the cd below.
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
cd "$HERE"

OUT_DIR="$HERE/bin"
LOG_DIR="$OUT_DIR/logs"

# Warnings monkeyc emits that we accept, matched against its output. fr55 and
# instinct2 run Connect IQ 3.4.2 and a watch-app glance needs 4.0.0, so the
# (:glance) annotation and the glance-scoped strings are ignored on those two.
# Keeping them in the matrix is deliberate (README.md, « Matrice d'appareils »).
# Anything else is a build failure: this is the Monkey C equivalent of
# `swiftlint --strict`.
#
# The exemption is scoped to those two devices on purpose. monkeyc prefixes
# every warning with the device it came from ("WARNING: fr55: …"), including
# during `--package-app`, where all seven devices land in a single log — so an
# unscoped pattern would forgive the same warning on a CIQ 4+ device, where it
# would mean the glance genuinely broke. Every other device stays at zero
# tolerance.
GLANCELESS_DEVICES='fr55|instinct2'
GLANCE_WARNINGS='Glance applications are not supported for app type|specifies the .glance. resource scope'
ACCEPTED_WARNINGS="^WARNING: ($GLANCELESS_DEVICES): .*($GLANCE_WARNINGS)"

die() {
    echo "erreur : $*" >&2
    exit 1
}

# ---------------------------------------------------------------- toolchain

resolve_java() {
    if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
        if [ -x /opt/homebrew/opt/openjdk@21/bin/java ]; then
            JAVA_HOME=/opt/homebrew/opt/openjdk@21
        elif [ -x /usr/libexec/java_home ] && /usr/libexec/java_home >/dev/null 2>&1; then
            JAVA_HOME="$(/usr/libexec/java_home)"
        else
            die "aucun JDK trouvé. Installer openjdk (brew install openjdk@21) ou définir JAVA_HOME."
        fi
    fi
    export JAVA_HOME
    # bin/monkeyc invokes a bare `java`. On macOS /usr/bin/java honours
    # JAVA_HOME, but a Homebrew JDK is keg-only and not on PATH by default —
    # put it there rather than depend on that shim.
    export PATH="$JAVA_HOME/bin:$PATH"
}

resolve_sdk() {
    if [ -n "${CIQ_SDK_HOME:-}" ]; then
        SDK="${CIQ_SDK_HOME%/}"
    else
        local config="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
        [ -f "$config" ] || die "SDK Connect IQ introuvable. Définir CIQ_SDK_HOME ou installer le SDK Manager."
        SDK="$(tr -d '\n' <"$config")"
        SDK="${SDK%/}"
    fi
    [ -x "$SDK/bin/monkeyc" ] || die "$SDK/bin/monkeyc introuvable ou non exécutable."
}

resolve_key() {
    KEY="${CIQ_DEVELOPER_KEY:-$HOME/.garmin/foulee_developer_key.der}"
    # Never printed, never copied: monkeyc reads it straight from $HOME.
    [ -f "$KEY" ] || die "clé développeur introuvable ($KEY). Voir README.md, « Prérequis »."
}

# Device ids, in manifest order — the manifest stays the single source of truth.
# `grep -o` rather than a line-oriented sed: two products on one line would
# silently lose one, and a device that never gets compiled is the exact bug
# this file exists to prevent.
manifest_devices() {
    grep -o '<iq:product[[:space:]]\{1,\}id="[^"]*"' manifest.xml |
        sed 's/.*id="//; s/"$//'
}

# ---------------------------------------------------------------- commands

cmd_validate() {
    python3 tools/validate_project.py
}

# compile <device> <output> [extra monkeyc args…]
compile_one() {
    local device="$1" output="$2"
    shift 2
    local log="$LOG_DIR/$device.log"

    printf '  %-14s ' "$device"
    if ! "$SDK/bin/monkeyc" \
        --jungles monkey.jungle \
        --device "$device" \
        --output "$output" \
        --private-key "$KEY" \
        --warn \
        --typecheck 3 \
        "$@" >"$log" 2>&1; then
        echo "ÉCHEC"
        sed 's/^/      /' "$log"
        return 1
    fi

    local warnings unexpected
    warnings=$(grep -c '^WARNING' "$log" || true)
    unexpected=$(grep '^WARNING' "$log" | grep -Ev "$ACCEPTED_WARNINGS" || true)
    if [ -n "$unexpected" ]; then
        echo "ÉCHEC (avertissement non attendu)"
        printf '%s\n' "$unexpected" | sed 's/^/      /'
        return 1
    fi

    local size
    size=$(wc -c <"$output" | tr -d ' ')
    echo "ok    ${size} octets, ${warnings} avertissement(s) attendu(s)"
}

cmd_build() {
    # No arrays or `mapfile` here: macOS still ships bash 3.2 as /bin/bash and
    # this script has to run under it too.
    local devices
    if [ "$#" -gt 0 ]; then
        devices="$*"
    else
        devices="$(manifest_devices)"
    fi
    [ -n "$devices" ] || die "aucun appareil dans manifest.xml"

    mkdir -p "$OUT_DIR" "$LOG_DIR"
    echo "Compilation ($SDK)"
    local failed=0
    for device in $devices; do
        compile_one "$device" "$OUT_DIR/foulee-$device.prg" || failed=1
    done
    [ "$failed" -eq 0 ] || die "au moins un appareil n'a pas compilé (journaux dans $LOG_DIR)"
    echo "Tous les appareils compilent en -w -l 3."
}

cmd_test() {
    local device="${1:-venu2}"
    mkdir -p "$OUT_DIR" "$LOG_DIR"
    echo "Compilation des tests unitaires"
    compile_one "$device" "$OUT_DIR/foulee-test-$device.prg" --unit-test
    cat <<EOF

Pour exécuter les tests, le simulateur doit tourner (interface graphique) :
  "\$SDK/bin/connectiq" &
  "\$SDK/bin/monkeydo" $OUT_DIR/foulee-test-$device.prg $device -t
EOF
}

cmd_package() {
    mkdir -p "$OUT_DIR" "$LOG_DIR"
    local output="$OUT_DIR/foulee.iq"
    local log="$LOG_DIR/package.log"

    echo "Construction du paquet store (.iq, tous les appareils du manifeste)"
    if ! "$SDK/bin/monkeyc" \
        --jungles monkey.jungle \
        --package-app \
        --output "$output" \
        --private-key "$KEY" \
        --warn \
        --typecheck 3 \
        --release >"$log" 2>&1; then
        sed 's/^/  /' "$log"
        die "l'export .iq a échoué"
    fi

    local unexpected
    unexpected=$(grep '^WARNING' "$log" | grep -Ev "$ACCEPTED_WARNINGS" || true)
    if [ -n "$unexpected" ]; then
        printf '%s\n' "$unexpected" | sed 's/^/  /'
        die "avertissement non attendu à l'export"
    fi

    echo "  $output ($(wc -c <"$output" | tr -d ' ') octets)"
    echo
    echo "À téléverser sur https://apps.garmin.com/developer/upload"
    echo "Fiche store et procédure : store/README.md"
}

# Print the header comment block above (minus the shebang) as the help text, so
# there is only one copy of it to keep true.
usage() {
    awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "$SELF"
}

main() {
    local command="${1:-build}"
    shift || true
    case "$command" in
        validate)
            cmd_validate
            ;;
        build | test | package)
            resolve_java
            resolve_sdk
            resolve_key
            "cmd_$command" "$@"
            ;;
        -h | --help | help)
            usage
            ;;
        *)
            usage >&2
            die "commande inconnue « $command »"
            ;;
    esac
}

main "$@"
