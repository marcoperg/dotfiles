#!/usr/bin/env bash
# Install packages required by system-backed dotfile integrations.
set -euo pipefail

install_apt() {
	local packages=(
		autoconf
		automake
		build-essential
		cmake
		hunspell
		hunspell-en-us
		hunspell-es
		isync
		latexmk
		libpoppler-glib-dev
		libtool-bin
		libvterm-dev
		maildir-utils
		msmtp
		mu4e
		pkg-config
	)

	printf '%s\n' 'Installing dependencies with apt-get...'
	sudo apt-get update
	sudo apt-get install --yes "${packages[@]}"
}

install_arch() {
	local packages=(
		base-devel
		cmake
		hunspell
		hunspell-en_us
		hunspell-es_es
		isync
		libtool
		libvterm
		msmtp
		pkgconf
		poppler-glib
		texlive-binextra
	)
	local aur_helper=""

	printf '%s\n' 'Installing dependencies with pacman...'
	sudo pacman --sync --refresh --sysupgrade --needed "${packages[@]}"

	command -v mu >/dev/null 2>&1 && return
	if command -v paru >/dev/null 2>&1; then
		aur_helper=paru
	elif command -v yay >/dev/null 2>&1; then
		aur_helper=yay
	fi

	if [[ -n "$aur_helper" ]]; then
		printf 'Installing mu/mu4e from the AUR with %s...\n' "$aur_helper"
		"$aur_helper" --sync --needed mu
	else
		printf '%s\n' \
			'install-system-deps: mu/mu4e requires the AUR package mu; install it with paru or yay' >&2
	fi
}

install_brew_tex() {
	command -v latexmk >/dev/null 2>&1 && return

	if ! command -v tlmgr >/dev/null 2>&1; then
		printf '%s\n' 'Installing BasicTeX with Homebrew...'
		brew install --cask basictex
		export PATH="/Library/TeX/texbin:$PATH"
	fi

	if command -v tlmgr >/dev/null 2>&1; then
		printf '%s\n' 'Installing latexmk with tlmgr...'
		sudo "$(command -v tlmgr)" update --self
		sudo "$(command -v tlmgr)" install latexmk
	else
		printf '%s\n' \
			'install-system-deps: open a new shell, run sudo tlmgr install latexmk, then rerun this script' >&2
	fi
}

install_brew() {
	local packages=(
		autoconf
		automake
		cmake
		hunspell
		isync
		libtool
		libvterm
		msmtp
		mu
		pkg-config
		poppler
	)

	if [[ "$(uname -s)" == "Darwin" ]] && ! xcode-select -p >/dev/null 2>&1; then
		printf '%s\n' \
			'install-system-deps: install Xcode Command Line Tools with xcode-select --install, then rerun' >&2
		exit 1
	fi

	printf '%s\n' 'Installing dependencies with Homebrew...'
	brew install "${packages[@]}"
	[[ "$(uname -s)" != "Darwin" ]] || install_brew_tex

	if [[ "$(uname -s)" == "Darwin" ]]; then
		printf '%s\n' \
			'Homebrew does not ship Hunspell dictionaries; place .aff/.dic files in ~/Library/Spelling/'
	fi
}

if command -v apt-get >/dev/null 2>&1; then
	install_apt
elif command -v pacman >/dev/null 2>&1; then
	install_arch
elif command -v brew >/dev/null 2>&1; then
	install_brew
else
	printf '%s\n' \
		'install-system-deps: supported package managers are apt-get, pacman, and Homebrew' >&2
	exit 1
fi
