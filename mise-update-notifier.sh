#!/bin/bash
#
# mise-update-notifier.sh
# Notifie quand des packages mise ont des mises à jour disponibles
#

set -euo pipefail

# Configuration
MISE_BIN="${MISE_BIN:-$HOME/.local/bin/mise}"
CACHE_FILE="${CACHE_FILE:-$HOME/.cache/mise-notifier-last}"
NOTIFY_CMD="terminal-notifier"
DIALOG_SCRIPT="${DIALOG_SCRIPT:-$HOME/Bin/mise-update-dialog.sh}"

# Vérifie que mise est disponible
check_dependencies() {
    if [[ ! -x "$MISE_BIN" ]]; then
        echo "Erreur: mise non trouvé à $MISE_BIN" >&2
        exit 1
    fi

    if ! command -v "$NOTIFY_CMD" &>/dev/null; then
        echo "Erreur: $NOTIFY_CMD non installé (brew install terminal-notifier)" >&2
        exit 1
    fi
}

# Récupère les packages outdated
get_outdated_packages() {
    "$MISE_BIN" outdated 2>/dev/null || true
}

# Formate le message de notification
# Entrée: liste des packages outdated (une ligne par package)
# Sortie: titre (ligne 1) + message (lignes suivantes)
format_notification_message() {
    local outdated_list="$1"
    local count
    count=$(echo "$outdated_list" | wc -l | tr -d ' ')

    # Titre avec le nombre de mises à jour
    if [[ "$count" -eq 1 ]]; then
        echo "🔄 1 mise à jour mise"
    else
        echo "🔄 $count mises à jour mise"
    fi

    # Message: liste les 5 premiers packages avec versions
    local shown=0
    while IFS=' ' read -r name _ installed latest _; do
        [[ -z "$name" ]] && continue
        echo "$name $installed → $latest"
        ((shown++))
        [[ $shown -ge 5 ]] && break
    done <<< "$outdated_list"

    # Indique s'il y en a plus
    if [[ "$count" -gt 5 ]]; then
        echo "... et $((count - 5)) autre(s)"
    fi
}

# Envoie la notification macOS (cliquable)
send_notification() {
    local title="$1"
    local message="$2"

    "$NOTIFY_CMD" \
        -title "$title" \
        -message "$message" \
        -sound "default" \
        -group "mise-updates" \
        -execute "$DIALOG_SCRIPT"
}

# Vérifie si on a déjà notifié pour cette liste
should_notify() {
    local current_hash="$1"

    mkdir -p "$(dirname "$CACHE_FILE")"

    if [[ -f "$CACHE_FILE" ]]; then
        local last_hash
        last_hash=$(cat "$CACHE_FILE")
        [[ "$current_hash" != "$last_hash" ]]
    else
        return 0
    fi
}

save_notification_state() {
    local hash="$1"
    echo "$hash" > "$CACHE_FILE"
}

# Main
main() {
    check_dependencies

    local outdated
    outdated=$(get_outdated_packages)

    if [[ -z "$outdated" ]]; then
        echo "Tous les packages sont à jour ✓"
        exit 0
    fi

    # Hash pour éviter les notifications répétées
    local hash
    hash=$(echo "$outdated" | md5)

    if should_notify "$hash"; then
        local formatted
        formatted=$(format_notification_message "$outdated")

        # Première ligne = titre, reste = message
        local title message
        title=$(echo "$formatted" | head -1)
        message=$(echo "$formatted" | tail -n +2)

        send_notification "$title" "$message"
        save_notification_state "$hash"

        echo "Notification envoyée: $title"
    else
        echo "Déjà notifié pour ces mises à jour"
    fi
}

main "$@"
