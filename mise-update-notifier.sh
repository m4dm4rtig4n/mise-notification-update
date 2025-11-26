#!/bin/bash
#
# mise-update-notifier.sh
# Notifie quand des packages mise ou Homebrew ont des mises à jour disponibles
#

set -euo pipefail

# Configuration
MISE_BIN="${MISE_BIN:-$HOME/.local/bin/mise}"
BREW_BIN="${BREW_BIN:-/opt/homebrew/bin/brew}"
CACHE_FILE="${CACHE_FILE:-$HOME/.cache/mise-notifier-last}"
NOTIFY_CMD="terminal-notifier"
DIALOG_APP="${DIALOG_APP:-$HOME/Bin/MiseUpdater.app}"

# Vérifie les dépendances
check_dependencies() {
    if ! command -v "$NOTIFY_CMD" &>/dev/null; then
        echo "Erreur: $NOTIFY_CMD non installé (brew install terminal-notifier)" >&2
        exit 1
    fi
}

# Récupère les packages mise outdated
get_mise_outdated() {
    if [[ -x "$MISE_BIN" ]]; then
        "$MISE_BIN" outdated 2>/dev/null | while read -r line; do
            [[ -z "$line" ]] && continue
            echo "mise:$line"
        done
    fi
}

# Récupère les packages brew outdated
get_brew_outdated() {
    if [[ -x "$BREW_BIN" ]]; then
        "$BREW_BIN" outdated --verbose 2>/dev/null | while read -r line; do
            [[ -z "$line" ]] && continue
            echo "brew:$line"
        done
    fi
}

# Récupère tous les packages outdated
get_all_outdated() {
    {
        get_mise_outdated
        get_brew_outdated
    } | grep -v '^$' || true
}

# Formate le message de notification
format_notification_message() {
    local outdated_list="$1"
    local count
    count=$(echo "$outdated_list" | wc -l | tr -d ' ')

    local mise_count brew_count
    mise_count=$(echo "$outdated_list" | grep -c "^mise:" || true)
    brew_count=$(echo "$outdated_list" | grep -c "^brew:" || true)

    # Titre avec le nombre de mises à jour
    if [[ "$count" -eq 1 ]]; then
        echo "🔄 1 mise à jour disponible"
    else
        echo "🔄 $count mises à jour disponibles"
    fi

    # Message: liste les 5 premiers packages avec versions
    local shown=0
    while IFS=':' read -r source rest; do
        [[ -z "$source" ]] && continue

        local name current new icon
        if [[ "$source" == "mise" ]]; then
            icon="🔧"
            # Format mise: "name tool installed latest"
            read -r name _ current new _ <<< "$rest"
        else
            icon="🍺"
            # Format brew: "name (current) < new" or "name (current) != new"
            # Parse manually to avoid regex issues
            name="${rest%% *}"
            local temp="${rest#* (}"
            current="${temp%%)*}"
            new="${rest##* }"
        fi

        echo "$icon $name $current → $new"
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
        -open "file://$DIALOG_APP"
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
    outdated=$(get_all_outdated)

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
