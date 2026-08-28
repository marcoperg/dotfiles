#!/usr/bin/env bash
# Install packages required by system-backed dotfile integrations.
set -euo pipefail

readonly MU_VERSION=1.12.15
readonly MU_SHA256=49d75622acff9d8a552622eba29d8abe49ae26d7fe80d835898f75f43e673ee3

install_mu_local() {
	local archive current_version meson_bin source_dir user_base work_dir
	local meson_version version_output

	version_output=$(mu --version 2>/dev/null || true)
	if [[ "$version_output" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
		current_version=${BASH_REMATCH[1]}
		if dpkg --compare-versions "$current_version" ge "$MU_VERSION"; then
			printf 'mu %s is already installed.\n' "$current_version"
			return
		fi
	fi

	printf 'Installing mu %s under ~/.local...\n' "$MU_VERSION"
	meson_bin=$(command -v meson || true)
	meson_version=""
	if [[ -n "$meson_bin" ]]; then
		meson_version=$("$meson_bin" --version 2>/dev/null || true)
	fi
	if [[ -z "$meson_version" ]] || dpkg --compare-versions "$meson_version" lt 0.56; then
		python3 -m pip install --user --upgrade 'meson>=0.56'
		user_base=$(python3 -m site --user-base)
		meson_bin="$user_base/bin/meson"
	fi
	if [[ ! -x "$meson_bin" ]]; then
		printf 'install-system-deps: Meson was not installed at %s\n' "$meson_bin" >&2
		exit 1
	fi

	work_dir=$(mktemp --directory)
	archive="$work_dir/mu-$MU_VERSION.tar.xz"
	source_dir="$work_dir/mu-$MU_VERSION"
	curl --fail --location --output "$archive" \
		"https://github.com/djcb/mu/releases/download/v$MU_VERSION/mu-$MU_VERSION.tar.xz"
	printf '%s  %s\n' "$MU_SHA256" "$archive" | sha256sum --check --status
	tar --extract --file "$archive" --directory "$work_dir"

	"$meson_bin" setup "$source_dir/build" "$source_dir" \
		--buildtype=release \
		--prefix="$HOME/.local" \
		-Dcld2=disabled \
		-Dguile=disabled \
		-Dreadline=disabled \
		-Dscm=disabled \
		-Dtests=disabled
	"$meson_bin" compile --verbose -C "$source_dir/build"
	"$meson_bin" install --no-rebuild -C "$source_dir/build"
	rm -rf "$work_dir"
}

install_apt() {
	local packages=(
		autoconf
		automake
		build-essential
		cmake
		curl
		hunspell
		hunspell-en-us
		hunspell-es
		isync
		latexmk
		libglib2.0-dev
		libgmime-3.0-dev
		libpoppler-glib-dev
		libtool-bin
		libvterm-dev
		libxapian-dev
		maildir-utils
		meson
		msmtp
		mu4e
		ninja-build
		pkg-config
		python3-pip
		xz-utils
	)

	printf '%s\n' 'Installing dependencies with apt-get...'
	sudo apt-get update
	sudo apt-get install --yes "${packages[@]}"
	install_mu_local
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
