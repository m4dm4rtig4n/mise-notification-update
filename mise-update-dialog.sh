#!/bin/bash
#
# mise-update-dialog.sh
# Affiche un dialogue SwiftDialog avec les mises à jour et exécute mise upgrade
#

set -euo pipefail

MISE_BIN="${MISE_BIN:-$HOME/.local/bin/mise}"
DIALOG_BIN="/usr/local/bin/dialog"
COMMAND_FILE="/tmp/mise-dialog-cmd-$$"
LOG_FILE="/tmp/mise-upgrade-log-$$"

cleanup() {
    rm -f "$COMMAND_FILE" "$LOG_FILE"
}
trap cleanup EXIT

# Génère la liste des packages pour SwiftDialog (format JSON)
get_package_list_json() {
    local first=true
    echo -n "["
    "$MISE_BIN" outdated 2>/dev/null | while IFS=' ' read -r name _ installed latest _; do
        [[ -z "$name" ]] && continue
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo -n ","
        fi
        echo -n "{\"title\":\"$name\",\"status\":\"$installed → $latest\",\"icon\":\"SF=shippingbox\"}"
    done
    echo "]"
}

# Affiche le dialogue de confirmation avec SwiftDialog
show_confirmation_dialog() {
    local count="$1"
    local package_json="$2"

    "$DIALOG_BIN" \
        --title "Mise - Mises à jour disponibles" \
        --message "**$count mise(s) à jour disponible(s)**\n\nVoulez-vous les installer ?" \
        --icon "SF=arrow.triangle.2.circlepath.circle.fill" \
        --iconsize 80 \
        --button1text "Mettre à jour" \
        --button2text "Annuler" \
        --infobox "### Packages\n\n$package_json" \
        --listitem "$package_json" \
        --liststyle compact \
        --width 500 \
        --height 400 \
        --json 2>/dev/null

    return $?
}

# Affiche le dialogue de progression avec log en temps réel
run_upgrade_with_dialog() {
    touch "$COMMAND_FILE"

    # Fichier temporaire pour accumuler les logs
    local log_file="/tmp/mise-log-$$"
    : > "$log_file"

    # Lance le dialogue en arrière-plan
    "$DIALOG_BIN" \
        --title "" \
        --titlefont "size=0" \
        --message "### ⏳ Installation en cours..." \
        --messagefont "name=Menlo,size=11" \
        --progress 100 \
        --progresstext "Préparation..." \
        --button1text "Fermer" \
        --button1disabled \
        --width 500 \
        --height 280 \
        --moveable \
        --ontop \
        --hideicon \
        --commandfile "$COMMAND_FILE" &

    local dialog_pid=$!
    sleep 0.3

    local total_packages
    total_packages=$("$MISE_BIN" outdated 2>/dev/null | wc -l | tr -d ' ')
    local current=0

    # Mise à jour avec capture ligne par ligne
    "$MISE_BIN" upgrade 2>&1 | while IFS= read -r line; do
        echo "$line" >> "$log_file"

        # Affiche les 8 dernières lignes formatées
        local display_log
        display_log=$(tail -8 "$log_file" | sed 's/^/▸ /')

        echo "message: ### ⏳ Installation...\n\n\`\`\`\n$display_log\n\`\`\`" >> "$COMMAND_FILE"

        # Progression
        if [[ "$line" == *"✓"* ]]; then
            ((current++)) || true
            local percent=$((current * 100 / total_packages))
            [[ $percent -gt 100 ]] && percent=100
            echo "progress: $percent" >> "$COMMAND_FILE"
            echo "progresstext: $current / $total_packages" >> "$COMMAND_FILE"
        fi
    done

    # Finalise
    sleep 0.2
    local final_log
    final_log=$(tail -6 "$log_file" | sed 's/^/▸ /')

    echo "progress: 100" >> "$COMMAND_FILE"
    echo "progresstext: Terminé" >> "$COMMAND_FILE"
    echo "message: ### ✅ Terminé !\n\n\`\`\`\n$final_log\n\`\`\`" >> "$COMMAND_FILE"
    echo "button1: enable" >> "$COMMAND_FILE"

    rm -f "$log_file"
    wait $dialog_pid 2>/dev/null || true
}

# Main
main() {
    local outdated
    outdated=$("$MISE_BIN" outdated 2>/dev/null) || true

    if [[ -z "$outdated" ]]; then
        # Pas de popup si lancé en mode non-interactif (cron)
        if [[ -t 0 ]]; then
            "$DIALOG_BIN" \
                --title "Mise" \
                --message "✅ Tous les packages sont à jour" \
                --button1text "OK" \
                --mini \
                --hideicon
        fi
        exit 0
    fi

    local count
    count=$(echo "$outdated" | wc -l | tr -d ' ')

    # Formate la liste pour l'affichage
    local formatted_list
    formatted_list=$("$MISE_BIN" outdated 2>/dev/null | while read -r name _ installed latest _; do
        [[ -z "$name" ]] && continue
        echo "⬆️  **$name**  \`$installed\` → \`$latest\`"
    done)

    # Dialogue de confirmation
    if "$DIALOG_BIN" \
        --title "" \
        --titlefont "size=0" \
        --message "# 🚀 Mises à jour\n\n$formatted_list" \
        --messagefont "size=14" \
        --button1text "Installer" \
        --button2text "Plus tard" \
        --width 420 \
        --height 220 \
        --moveable \
        --ontop \
        --hideicon \
        --style centered 2>/dev/null
    then
        run_upgrade_with_dialog
    fi
}

main "$@"
