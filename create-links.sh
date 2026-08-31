#!/bin/bash
# ---
# dotfiles boostrap
#
# DON'T FREAK! It backs everything up to:
#   ~/.dotfiles.backups
#
# ...unless you've tampered with things


HOMEDIR=$HOME
BACKUPDIR="$HOMEDIR/.dotfiles.backups"
CURRENTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
DOTFILEDIR="$CURRENTDIR/dotfiles"


link_managed_file() {
	source_path="$DOTFILEDIR/$1"
	target_path="$HOMEDIR/$2"
	backup_path="$BACKUPDIR/$2"
	backup_count=1

	if [[ -L "$target_path" ]] && [[ "$(readlink "$target_path")" == "$source_path" ]]; then
		return
	fi

	if [[ -e "$target_path" ]] || [[ -L "$target_path" ]]; then
		while [[ -e "$backup_path" ]] || [[ -L "$backup_path" ]]; do
			backup_path="$BACKUPDIR/$2.$backup_count"
			((backup_count++))
		done
		mkdir -p "$(dirname "$backup_path")"
		mv "$target_path" "$backup_path"
	fi

	mkdir -p "$(dirname "$target_path")"
	ln -s "$source_path" "$target_path"
}

link_dotfile() {
	local target_path
	case "$1" in
		emacs) target_path=.emacs.d ;;
		nvim|i3) target_path=.config/$1 ;;
		*) target_path=$1 ;;
	esac
	link_managed_file "$1" "$target_path"
}

install_opencode_state_defaults() {
	local defaults_path="$DOTFILEDIR/opencode/state-defaults.json"
	local state_path="$HOMEDIR/.local/state/opencode/kv.json"
	local temp_path

	mkdir -p "$(dirname "$state_path")"
	if [[ ! -e "$state_path" ]]; then
		cp "$defaults_path" "$state_path"
		return
	fi

	if ! command -v jq >/dev/null 2>&1; then
		echo "jq is required to merge OpenCode state defaults into $state_path"
		return 1
	fi

	temp_path=$(mktemp "$state_path.XXXXXX")
	if jq -s '.[0] * .[1]' "$state_path" "$defaults_path" > "$temp_path"; then
		mv "$temp_path" "$state_path"
	else
		rm -f "$temp_path"
		return 1
	fi
}


install_user_services() {
	if [[ "$(uname -s)" != "Linux" ]] || ! command -v systemctl >/dev/null 2>&1; then
		return
	fi

	link_managed_file emacs/emacs.service .config/systemd/user/emacs.service
	link_managed_file opencode/opencode.service .config/systemd/user/opencode.service
	systemctl --user daemon-reload
	systemctl --user enable --now emacs.service

	if [[ ! -x "$HOMEDIR/.opencode/bin/opencode" ]]; then
		echo "OpenCode service installed but not started: $HOMEDIR/.opencode/bin/opencode is missing"
		return
	fi

	systemctl --user enable --now opencode.service
}


link_managed_configs() {
	link_managed_file .zshenv .zshenv
	link_managed_file claude/settings.json .claude/settings.json
	link_managed_file claude/keybindings.json .claude/keybindings.json
	link_managed_file opencode/opencode.jsonc .config/opencode/opencode.jsonc
	link_managed_file opencode/tui.jsonc .config/opencode/tui.jsonc
	install_opencode_state_defaults
	install_user_services
}


if [[ $SUDO_USER ]]; then
	echo "Running scripts you find on the internet as root is dangerous. Try again without 'sudo'."
	exit 1
fi


if [[ ! -e $BACKUPDIR ]]; then
	echo "Creating back ups folder $BACKUPDIR..."
	mkdir $BACKUPDIR
fi

if [[ "$1" == "--managed" ]]; then
	link_managed_configs
	exit 0
fi


dotfiles=$(ls -1 -A $DOTFILEDIR 2> /dev/null)

if [[ $dotfiles ]]; then
	echo "Symlinking dotfiles..."

	for dotfile in $dotfiles; do
		if [[ "$dotfile" == "claude" ]] || [[ "$dotfile" == "opencode" ]]; then
			continue
		fi
		echo "$dotfile"
		link_dotfile "$dotfile"
	done

	link_managed_configs

	git submodule update --init
	echo "All set! Any existing files were moved to $BACKUPDIR"

else
	echo "You don't have anything in '$DOTFILEDIR', bro-tato"
fi
