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
CURRENTDIR=$(pwd -P)
DOTFILEDIR="$CURRENTDIR/dotfiles"


backup_dotfile() {
	if [[ -e "$HOMEDIR/$1" ]]; then

		# Do we already have any backups? How many?
		# This needs some work. Doesn't handle things like
		# $BACKUPDIR/.vim* and $BACKUPDIR/.vimrc* well
		dotfile_count=$(find $BACKUPDIR/$1* -maxdepth 0 2> /dev/null | wc -l | sed 's/ //g')

		if [[ $dotfile_count -ne '0' ]]; then
			mv $HOMEDIR/$1 $BACKUPDIR/$1.$dotfile_count
		else
			mv $HOMEDIR/$1 $BACKUPDIR/$1
		fi
	fi
}

symlink_dotfile() {
	if [[ $DOTFILEDIR/$1 == *"nvim"* ]] | [[ $DOTFILEDIR/$1 == *"i3"* ]]; then
		ln -s $DOTFILEDIR/$1 $HOMEDIR/.config/$1
	else
		ln -s $DOTFILEDIR/$1 $HOMEDIR/$1
	fi
}

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

link_managed_configs() {
	link_managed_file .zshenv .zshenv
	link_managed_file claude/settings.json .claude/settings.json
	link_managed_file claude/keybindings.json .claude/keybindings.json
	link_managed_file opencode/opencode.jsonc .config/opencode/opencode.jsonc
	install_opencode_state_defaults
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
		backup_dotfile $dotfile
		symlink_dotfile $dotfile
	done

	link_managed_configs

	git submodule update --init
	echo "All set! Any existing files were moved to $BACKUPDIR"

else
	echo "You don't have anything in '$DOTFILEDIR', bro-tato"
fi
