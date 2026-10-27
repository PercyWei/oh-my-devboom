#!/usr/bin/env bash
# Only fixtures in a temporary HOME are changed; no installer is executed.
set -eu

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASH_BIN=${BASH:-bash}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_equal() {
    [[ "$1" == "$2" ]] || fail "$3 (expected: $1; actual: $2)"
}

if [[ $# -eq 0 ]]; then
    failures=0
    for test_case in detection arguments config idempotency packages remote fzf shell; do
        if "$BASH_BIN" "$0" "$test_case"; then
            printf 'PASS: %s\n' "$test_case"
        else
            failures=$((failures + 1))
        fi
    done
    [[ $failures -eq 0 ]] || exit 1
    printf 'All test groups passed.\n'
    exit 0
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/oh-my-devboom-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
unset ZDOTDIR
mkdir -p "$HOME" "$TEST_ROOT/bin"
export PATH="$TEST_ROOT/bin:$PATH"

case "$1" in
    detection)
        source "$REPO_ROOT/lib/common.sh"
        source "$REPO_ROOT/lib/system.sh"
        export OS_RELEASE_FILE="$TEST_ROOT/os-release"
        cat > "$OS_RELEASE_FILE" <<'RELEASE'
NAME="Debian GNU/Linux"
ID=debian
ID_LIKE=debian
RELEASE
        printf '#!/bin/sh\nexit 99\n' > "$TEST_ROOT/bin/apt-get"
        chmod +x "$TEST_ROOT/bin/apt-get"
        uname() {
            case "$1" in
                -s) printf 'Linux\n' ;;
                -m) printf 'aarch64\n' ;;
                *) return 1 ;;
            esac
        }
        id() { printf '4242\n'; }
        sudo() { fail 'Detection invoked sudo'; }
        unset container
        systemd-detect-virt() {
            assert_equal '--container --quiet' "$*" 'Container probe arguments'
            return 0
        }
        detect_system
        assert_equal linux "$OS" 'Linux detection'
        assert_equal debian "$DISTRO" 'Distro detection from os-release'
        assert_equal aarch64 "$ARCH" 'Linux architecture detection'
        assert_equal 4242 "$USER_ID" 'Non-root user detection'
        assert_equal apt-get "$PACKAGE_MANAGER" 'Linux package manager detection'
        assert_equal 1 "$HAS_SUDO" 'Available sudo is detected without execution'
        assert_equal 1 "$IN_CONTAINER" 'Containers without marker files can use systemd detection'

        printf '#!/bin/sh\nexit 99\n' > "$TEST_ROOT/bin/brew"
        chmod +x "$TEST_ROOT/bin/brew"
        uname() {
            case "$1" in
                -s) printf 'Darwin\n' ;;
                -m) printf 'arm64\n' ;;
                *) return 1 ;;
            esac
        }
        id() { printf '0\n'; }
        systemd-detect-virt() { fail 'macOS invoked the Linux container probe'; }
        detect_system
        assert_equal macos "$OS" 'macOS detection'
        assert_equal aarch64 "$ARCH" 'Apple Silicon normalization'
        assert_equal 0 "$USER_ID" 'Root user detection'
        assert_equal brew "$PACKAGE_MANAGER" 'macOS package manager detection'

        uname() { printf 'FreeBSD\n'; }
        status=0
        detect_system || status=$?
        assert_equal 1 "$status" 'Unsupported systems are rejected'
        ;;
    arguments)
        output=$("$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --help)
        [[ "$output" == *--config* && "$output" == *--modules* && "$output" == *--allow-remote* ]] || fail 'Help documents config, module and remote options'
        output=$("$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --list-modules)
        for module in base homebrew zsh powerlevel10k tools dotfiles; do
            [[ "$output" == *"$module"* ]] || fail "Missing module in list: $module"
        done
        [[ "$output" != *starship* ]] || fail 'Removed Starship module is still listed'
        source "$REPO_ROOT/bootstrap.sh"
        parse_args --non-interactive
        assert_equal 'base homebrew zsh powerlevel10k dotfiles' "$MODULES" 'Default modules include Powerlevel10k'
        assert_equal 'fzf rg bat eza zoxide nvtop jq fd uv zellij' "$TOOLS" 'Default tools follow the grouped config order'
        parse_args --modules powerlevel10k --non-interactive
        assert_equal powerlevel10k "$MODULES" 'Powerlevel10k module is accepted'
        parse_args --modules tools --tools zellij,nvtop,jq,fd --non-interactive
        assert_equal 'zellij nvtop jq fd' "$TOOLS" 'Zellij, nvtop, jq and fd are accepted tools'
        parse_args --modules all --tools all --non-interactive
        assert_equal "$AVAILABLE_MODULES" "$MODULES" 'all selects every module'
        assert_equal "$AVAILABLE_TOOLS" "$TOOLS" 'all selects every optional tool'

        config_file="$TEST_ROOT/custom config.conf"
        # Comments, whitespace and a final line without a newline are supported.
        printf '# Selected tools\n\n[modules]\nbase = false\ntools = true\n[tools]\njq = true # JSON\nfd = false\n[options]\nallow_remote = false\nconflict = backup' > "$config_file"
        parse_args --config "$config_file" --non-interactive
        assert_equal tools "$MODULES" 'Custom config replaces the default module selection'
        assert_equal jq "$TOOLS" 'Only enabled tools from the custom config are selected'
        assert_equal 0 "$ALLOW_REMOTE" 'Config can leave remote code unauthorized'
        assert_equal backup "$CONFLICT_POLICY" 'The final config line is read without a newline'
        output=$(print_install_plan "$AVAILABLE_MODULES")
        [[ "$output" == *"$config_file"* && "$output" == *'  tools: jq'* ]] || fail 'Plan omits config source or selected tools'
        parse_args --modules dotfiles --tools fd --allow-remote --conflict skip --config "$config_file" --non-interactive
        assert_equal 'dotfiles|fd|1|skip' "$MODULES|$TOOLS|$ALLOW_REMOTE|$CONFLICT_POLICY" 'CLI overrides config when placed before --config'
        parse_args --config "$config_file" --modules dotfiles --tools fd --allow-remote --conflict skip --non-interactive
        assert_equal 'dotfiles|fd|1|skip' "$MODULES|$TOOLS|$ALLOW_REMOTE|$CONFLICT_POLICY" 'CLI overrides config when placed after --config'

        printf '[options]\nallow_remote=true\nconflict=backup\n' > "$TEST_ROOT/options.conf"
        parse_args --config "$TEST_ROOT/options.conf" --non-interactive
        assert_equal '||1|backup' "$MODULES|$TOOLS|$ALLOW_REMOTE|$CONFLICT_POLICY" 'Omitted module and tool selections stay empty'
        : > "$TEST_ROOT/empty.conf"
        parse_args --config "$TEST_ROOT/empty.conf" --non-interactive
        assert_equal '||0|skip' "$MODULES|$TOOLS|$ALLOW_REMOTE|$CONFLICT_POLICY" 'Loading another config resets selections and safe options'
        output=$("$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --config "$TEST_ROOT/empty.conf" --non-interactive)
        [[ "$output" == *'未选择安装模块'* ]] || fail 'An empty config should complete without installation'

        for contents in '[unknown]' '[modules]\nunknown=true' '[tools]\nfzf=true\nfzf=false' \
            '[modules]\nbase=yes' '[options]\nconflict=replace' '[modules]\nbase' '[modules]\nbase="true"'; do
            printf '%b\n' "$contents" > "$TEST_ROOT/invalid.conf"
            if parse_args --config "$TEST_ROOT/invalid.conf" --non-interactive > "$TEST_ROOT/output" 2>&1; then
                fail "Invalid config was accepted: $contents"
            fi
            [[ "$(cat "$TEST_ROOT/output")" == *"$TEST_ROOT/invalid.conf:"* ]] || fail 'Config diagnostics omit the file and line'
        done
        printf '[modules]\nbase=$(touch "%s")\n' "$TEST_ROOT/config-executed" > "$TEST_ROOT/invalid.conf"
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --config "$TEST_ROOT/invalid.conf" --modules dotfiles --non-interactive > "$TEST_ROOT/output" 2>&1; then
            fail 'Executable config content was accepted'
        fi
        [[ ! -e "$TEST_ROOT/config-executed" ]] || fail 'Config content was executed'
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --config "$TEST_ROOT/missing.conf" --non-interactive > "$TEST_ROOT/output" 2>&1; then
            fail 'Missing config was accepted'
        fi
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --config "$TEST_ROOT/missing.conf" --help > "$TEST_ROOT/output"
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --config "$TEST_ROOT/missing.conf" --list-modules > "$TEST_ROOT/output"
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --non-interactive --unknown > "$TEST_ROOT/output" 2>&1; then
            fail 'Unknown option was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules unknown --non-interactive > "$TEST_ROOT/output" 2>&1; then
            fail 'Unknown module was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules starship --non-interactive > "$TEST_ROOT/output" 2>&1; then
            fail 'Removed Starship module was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --tools unknown --non-interactive > "$TEST_ROOT/output" 2>&1; then
            fail 'Unknown tool was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --conflict replace --non-interactive > "$TEST_ROOT/output" 2>&1; then
            fail 'Unknown conflict policy was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules > "$TEST_ROOT/output" 2>&1; then
            fail 'Missing option value was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --config > "$TEST_ROOT/output" 2>&1; then
            fail 'Missing config path was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles < /dev/null > "$TEST_ROOT/output" 2>&1; then
            fail 'Non-interactive execution without --non-interactive was accepted'
        fi
        [[ ! -e "$HOME/.zshrc" && ! -e "$HOME/.gitconfig" ]] || fail 'Argument checks changed HOME'

        printf '[modules]\ndotfiles=true\n[tools]\njq=true\n' > "$config_file"
        output=$("$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --config "$config_file" --non-interactive)
        [[ -L "$HOME/.zshrc" && -L "$HOME/.gitconfig" ]] || fail 'Custom config did not deploy selected dotfiles'
        [[ "$output" == *'  dotfiles:'* && "$output" == *'未启用 tools 模块'* && "$output" != *'  tools:'* ]] || fail 'Plan presents disabled optional tools as installation targets'
        ;;
    config)
        source "$REPO_ROOT/lib/common.sh"
        source "$REPO_ROOT/lib/config.sh"
        printf 'managed config\n' > "$TEST_ROOT/source"
        CONFLICT_POLICY=skip
        link_config "$TEST_ROOT/source" "$HOME/new/config"
        [[ -L "$HOME/new/config" ]] || fail 'Fresh config is not a symlink'
        assert_equal "$TEST_ROOT/source" "$(readlink "$HOME/new/config")" 'Symlink target'

        printf 'personal config\n' > "$HOME/existing"
        status=0
        link_config "$TEST_ROOT/source" "$HOME/existing" || status=$?
        assert_equal 2 "$status" 'Skip reports a conflict'
        [[ ! -L "$HOME/existing" ]] || fail 'Skip replaced a user file'
        assert_equal 'personal config' "$(cat "$HOME/existing")" 'Skip preserves contents'

        CONFLICT_POLICY=backup
        link_config "$TEST_ROOT/source" "$HOME/existing"
        shopt -s nullglob
        backups=("$HOME/existing.backup."*)
        assert_equal 1 "${#backups[@]}" 'One backup was created'
        assert_equal 'personal config' "$(cat "${backups[0]}")" 'Backup preserves contents'
        [[ -L "$HOME/existing" ]] || fail 'Backup did not deploy a symlink'

        mkdir -p "$HOME/directory"
        printf 'keep directory\n' > "$HOME/directory/file"
        link_config "$TEST_ROOT/source" "$HOME/directory"
        backups=("$HOME/directory.backup."*)
        assert_equal 1 "${#backups[@]}" 'Directory conflict was backed up'
        assert_equal 'keep directory' "$(cat "${backups[0]}/file")" 'Directory contents were preserved'

        ln -s "$TEST_ROOT/missing" "$HOME/dangling"
        CONFLICT_POLICY=skip
        status=0
        link_config "$TEST_ROOT/source" "$HOME/dangling" || status=$?
        assert_equal 2 "$status" 'Dangling symlink is treated as a conflict'
        assert_equal "$TEST_ROOT/missing" "$(readlink "$HOME/dangling")" 'Dangling symlink was preserved'
        ;;
    idempotency)
        source "$REPO_ROOT/lib/common.sh"
        source "$REPO_ROOT/lib/config.sh"
        printf 'managed config\n' > "$TEST_ROOT/source"
        printf 'personal config\n' > "$HOME/existing"
        CONFLICT_POLICY=backup
        link_config "$TEST_ROOT/source" "$HOME/existing"
        first_target=$(readlink "$HOME/existing")
        link_config "$TEST_ROOT/source" "$HOME/existing"
        assert_equal "$first_target" "$(readlink "$HOME/existing")" 'Repeated link has the same target'
        shopt -s nullglob
        backups=("$HOME/existing.backup."*)
        assert_equal 1 "${#backups[@]}" 'Repeated deployment creates no new backup'

        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --non-interactive > "$TEST_ROOT/first-run.log" 2>&1 || { cat "$TEST_ROOT/first-run.log" >&2; fail 'First dotfiles run failed'; }
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --non-interactive > "$TEST_ROOT/second-run.log" 2>&1 || { cat "$TEST_ROOT/second-run.log" >&2; fail 'Second dotfiles run failed'; }
        [[ -L "$HOME/.zshrc" ]] || fail 'Dotfiles module did not deploy .zshrc'
        [[ -L "$HOME/.gitconfig" ]] || fail 'Dotfiles module did not deploy .gitconfig'
        [[ -L "$HOME/.p10k.zsh" ]] || fail 'Dotfiles module did not deploy .p10k.zsh'
        assert_equal "$REPO_ROOT/config/powerlevel10k/p10k.zsh" "$(readlink "$HOME/.p10k.zsh")" 'Powerlevel10k preset source'
        [[ -z "$(find "$HOME" -name '*.backup.*' ! -path "$HOME/existing.backup.*" -print)" ]] || fail 'Repeated CLI deployment made unexpected backups'

        export ZDOTDIR="$HOME/custom-zsh"
        mkdir -p "$ZDOTDIR"
        printf 'personal prompt\n' > "$ZDOTDIR/.p10k.zsh"
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --non-interactive > "$TEST_ROOT/skip-run.log" 2>&1 || { cat "$TEST_ROOT/skip-run.log" >&2; fail 'Dotfiles skip run failed'; }
        [[ -L "$ZDOTDIR/.zshrc" ]] || fail 'Dotfiles module did not respect ZDOTDIR for .zshrc'
        [[ ! -L "$ZDOTDIR/.p10k.zsh" ]] || fail 'Default skip policy replaced a personal Powerlevel10k preset'
        assert_equal 'personal prompt' "$(cat "$ZDOTDIR/.p10k.zsh")" 'Skipped Powerlevel10k preset is preserved'
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --non-interactive --conflict backup > "$TEST_ROOT/backup-run.log" 2>&1 || { cat "$TEST_ROOT/backup-run.log" >&2; fail 'Dotfiles backup run failed'; }
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --non-interactive --conflict backup > "$TEST_ROOT/repeated-backup-run.log" 2>&1 || { cat "$TEST_ROOT/repeated-backup-run.log" >&2; fail 'Repeated dotfiles backup run failed'; }
        [[ -L "$ZDOTDIR/.p10k.zsh" ]] || fail 'Dotfiles module did not respect ZDOTDIR for .p10k.zsh'
        assert_equal "$REPO_ROOT/config/powerlevel10k/p10k.zsh" "$(readlink "$ZDOTDIR/.p10k.zsh")" 'ZDOTDIR Powerlevel10k preset source'
        backups=("$ZDOTDIR/.p10k.zsh.backup."*)
        assert_equal 1 "${#backups[@]}" 'Repeated Powerlevel10k deployment creates one backup'
        assert_equal 'personal prompt' "$(cat "${backups[0]}")" 'Powerlevel10k backup preserves contents'
        ;;
    packages)
        source "$REPO_ROOT/lib/common.sh"
        source "$REPO_ROOT/lib/packages.sh"
        available='git curl batcat fdfind'
        have() { [[ " $available " == *" $1 "* ]]; }
        apt-get() { printf '%s\n' "apt-get $*" >> "$TEST_ROOT/packages.log"; }
        PACKAGE_MANAGER=apt-get
        PACKAGES_REFRESHED=0
        USER_ID=0
        HAS_SUDO=0
        INTERACTIVE=0
        ensure_packages git curl bat fd
        [[ ! -e "$TEST_ROOT/packages.log" ]] || fail 'Present commands invoked a package manager'
        available='git curl batcat'
        ensure_packages git curl bat rg
        available="$available rg"
        ensure_packages eza
        available="$available eza"
        ensure_packages zellij nvtop
        available="$available zellij nvtop"
        ensure_packages jq fd
        available="$available jq fdfind"
        ensure_packages git curl bat rg eza zellij nvtop jq fd
        expected=$(printf 'apt-get update\napt-get install -y ripgrep\napt-get install -y eza\napt-get install -y zellij nvtop\napt-get install -y jq fd-find')
        assert_equal "$expected" "$(cat "$TEST_ROOT/packages.log")" 'Only missing packages install; apt refreshes once'
        USER_ID=4242
        status=0
        ensure_packages zoxide || status=$?
        assert_equal 2 "$status" 'Missing root or sudo access reports a skip'
        assert_equal "$expected" "$(cat "$TEST_ROOT/packages.log")" 'Unprivileged execution never invoked the manager'

        USER_ID=0
        available=fdfind
        dnf() { printf '%s\n' "dnf $*" >> "$TEST_ROOT/packages.log"; }
        yum() { printf '%s\n' "yum $*" >> "$TEST_ROOT/packages.log"; }
        for package_manager in dnf yum; do
            PACKAGE_MANAGER=$package_manager
            ensure_packages fd
        done
        assert_equal "$expected" "$(cat "$TEST_ROOT/packages.log")" 'RPM managers skip an available fdfind command'
        available=''
        for package_manager in dnf yum; do
            PACKAGE_MANAGER=$package_manager
            ensure_packages jq fd
        done
        expected=$(printf '%s\ndnf install -y jq fd-find\nyum install -y jq fd-find' "$expected")
        assert_equal "$expected" "$(cat "$TEST_ROOT/packages.log")" 'RPM managers map fd to fd-find and preserve jq'

        PACKAGE_MANAGER=apt-get
        apt-get() { return "$package_exit"; }
        for package_exit in 100 2; do
            status=0
            ensure_packages zoxide || status=$?
            assert_equal 1 "$status" "Package installer exit $package_exit reports failure"
        done
        PACKAGES_REFRESHED=0
        status=0
        ensure_packages zoxide || status=$?
        assert_equal 1 "$status" 'Package index refresh failure is not a skip'

        source "$REPO_ROOT/modules/tools.sh"
        ensure_packages() { fail 'Tools module tried to install an available fdfind command'; }
        available=fdfind
        TOOLS=fd
        module_tools
        ;;
    remote)
        source "$REPO_ROOT/lib/common.sh"
        # Shorten only the fixed network timer; all processes belong to these fixtures.
        sleep() {
            if [[ "$1" == 120 ]]; then
                command sleep "$NETWORK_TIMER_SECONDS" &
                printf '%s\n' "$!" > "$NETWORK_TEST_DIR/timer.pid"
                wait "$!"
            else
                command sleep "$@"
            fi
        }
        cat > "$TEST_ROOT/git-download-fixture.sh" <<'FIXTURE'
printf '%s\n' "$$" > "$NETWORK_TEST_DIR/command.pid"
printf '%s\n' "$PPID" > "$NETWORK_TEST_DIR/helper.pid"
printf '%s %s %s\n' "$GIT_TERMINAL_PROMPT" "$GIT_HTTP_LOW_SPEED_LIMIT" "$GIT_HTTP_LOW_SPEED_TIME" > "$NETWORK_TEST_DIR/env"
[[ "$NETWORK_SCENARIO" != timeout ]] || trap '' TERM
[[ "$NETWORK_SCENARIO" != timeout_success ]] || trap 'exit 0' TERM
sleep 30 &
printf '%s\n' "$!" > "$NETWORK_TEST_DIR/child.pid"
case "$NETWORK_SCENARIO" in
    success) sleep 0.1; exit 0 ;;
    failure) sleep 0.1; exit 7 ;;
    *) wait ;;
esac
FIXTURE
        for NETWORK_SCENARIO in success failure timeout timeout_success cancel; do
            export NETWORK_SCENARIO NETWORK_TEST_DIR="$TEST_ROOT/$NETWORK_SCENARIO" NETWORK_TIMER_SECONDS=30
            mkdir -p "$NETWORK_TEST_DIR"
            case "$NETWORK_SCENARIO" in timeout*) NETWORK_TIMER_SECONDS=0.2 ;; esac
            status=0
            if [[ "$NETWORK_SCENARIO" == cancel ]]; then
                run_git_download "$BASH_BIN" "$TEST_ROOT/git-download-fixture.sh" > "$NETWORK_TEST_DIR/output" 2>&1 &
                helper_pid=$!
                for attempt in 1 2 3 4 5 6 7 8 9 10; do
                    [[ ! -f "$NETWORK_TEST_DIR/child.pid" ]] || break
                    command sleep 0.05
                done
                kill -TERM "$(cat "$NETWORK_TEST_DIR/helper.pid")"
                wait "$helper_pid" || status=$?
            else
                run_git_download "$BASH_BIN" "$TEST_ROOT/git-download-fixture.sh" > "$NETWORK_TEST_DIR/output" 2>&1 || status=$?
            fi
            expected=1
            [[ "$NETWORK_SCENARIO" != success ]] || expected=0
            assert_equal "$expected" "$status" "Git download $NETWORK_SCENARIO status"
            case "$NETWORK_SCENARIO" in
                timeout*) [[ "$(cat "$NETWORK_TEST_DIR/output")" == *'Git download timed out after 120 seconds'* ]] || fail 'Git timeout message was hidden' ;;
            esac
            assert_equal '0 1 30' "$(cat "$NETWORK_TEST_DIR/env")" 'Git timeout settings reach child commands'
            for pid_file in "$NETWORK_TEST_DIR/"*.pid; do
                child_pid=$(cat "$pid_file")
                if kill -0 "$child_pid" 2>/dev/null; then
                    fail "Git download $NETWORK_SCENARIO left a process: $child_pid"
                fi
            done
        done
        unset -f sleep
        have() { [[ "$1" == curl ]]; }
        curl() { printf '%s\n' "$*" > "$TEST_ROOT/downloader.args"; return 28; }
        status=0
        download_file https://example.invalid/installer.sh "$TEST_ROOT/installer" || status=$?
        assert_equal 1 "$status" 'Curl timeout is reported as a failure'
        args=$(cat "$TEST_ROOT/downloader.args")
        [[ " $args " == *' --connect-timeout 15 '* && " $args " == *' --max-time 300 '* &&
            " $args " == *' --speed-limit 1 '* && " $args " == *' --speed-time 60 '* &&
            " $args " == *' --retry 2 '* && " $args " == *' --retry-max-time 300 '* ]] || fail 'Curl download limits are missing'
        curl() { printf '%s\n' "$*" > "$TEST_ROOT/downloader.args"; }
        download_file https://example.invalid/release.tar.gz "$TEST_ROOT/release" 1800
        args=$(cat "$TEST_ROOT/downloader.args")
        [[ " $args " == *' --max-time 1800 '* && " $args " == *' --retry-max-time 300 '* &&
            " $args " == *' --speed-limit 1 '* && " $args " == *' --speed-time 60 '* ]] || fail 'Release downloads must allow slow progress while bounding stalls and retries'
        have() { [[ "$1" == wget ]]; }
        wget() { printf '%s\n' "$*" > "$TEST_ROOT/downloader.args"; return 4; }
        status=0
        download_file https://example.invalid/installer.sh "$TEST_ROOT/installer" || status=$?
        assert_equal 1 "$status" 'Wget network failure is reported as a failure'
        args=$(cat "$TEST_ROOT/downloader.args")
        [[ " $args " == *' -T 30 '* && " $args " == *' -t 3 '* ]] || fail 'Wget download limits are missing'
        download_file() { touch "$TEST_ROOT/download-called"; fail 'Unauthorized installer download'; }
        INTERACTIVE=0
        ALLOW_REMOTE=0
        status=0
        run_remote_installer example https://example.invalid/installer.sh || status=$?
        assert_equal 2 "$status" 'Unauthorized non-interactive installer is skipped'
        [[ ! -e "$TEST_ROOT/download-called" && ! -e "$XDG_CACHE_HOME" ]] || fail 'Skipped installer created files'
        ;;
    fzf)
        source "$REPO_ROOT/lib/common.sh"
        source "$REPO_ROOT/lib/packages.sh"
        # Reproduce a container whose installed package has had doc files removed.
        sed "s|local scripts=/usr/share/doc/fzf/examples|local scripts=\"$TEST_ROOT/missing-docs\"|" \
            "$REPO_ROOT/modules/tools.sh" > "$TEST_ROOT/tools.sh"
        source "$TEST_ROOT/tools.sh"
        mkdir -p "$TEST_ROOT/package-scripts"
        printf '# completion fixture\n' > "$TEST_ROOT/package-scripts/completion.zsh"
        printf '# key bindings fixture\n' > "$TEST_ROOT/package-scripts/key-bindings.zsh"
        fzf_mode=old
        apt_status=0
        package_owner=fzf
        fzf() {
            case "$1" in
                --zsh) [[ "$fzf_mode" == modern ]] ;;
                --version) printf '0.44.1 (debian)\n' ;;
                *) fail "Unexpected fzf invocation: $*" ;;
            esac
        }
        dpkg-query() {
            case "$1" in
                -S) printf '%s: %s\n' "$package_owner" "$2" ;;
                -W) printf '0.44.1-1\n' ;;
                *) fail "Unexpected dpkg-query invocation: $*" ;;
            esac
        }
        apt-get() {
            assert_equal '-o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 download fzf=0.44.1-1' "$*" 'Download uses the exact installed package version'
            printf '%s\n' "$*" >> "$TEST_ROOT/apt.log"
            touch fzf_0.44.1-1_amd64.deb
            return "$apt_status"
        }
        dpkg-deb() {
            [[ "$1" == -x && -f "$2" ]] || fail 'The downloaded package must be extracted, not installed'
            mkdir -p "$3/usr/share/doc/fzf/examples"
            cp "$TEST_ROOT/package-scripts/"* "$3/usr/share/doc/fzf/examples/"
        }
        TOOLS=fzf
        target="$XDG_DATA_HOME/oh-my-devboom/fzf"
        module_tools
        assert_equal '0.44.1 (debian)' "$(cat "$target/fzf-version")" 'Runtime records the actual fzf version'
        for script in completion.zsh key-bindings.zsh; do
            cmp "$TEST_ROOT/package-scripts/$script" "$target/$script" || fail 'Matching package scripts were not deployed'
        done
        downloaded=$(cat "$TEST_ROOT/apt.log")
        module_tools
        assert_equal "$downloaded" "$(cat "$TEST_ROOT/apt.log")" 'Repeated preparation must not download again'
        mv "$target" "$TEST_ROOT/prepared-fzf"
        fzf_mode=modern
        module_tools
        [[ ! -e "$target" ]] || fail 'Modern fzf does not need a runtime script cache'
        assert_equal "$downloaded" "$(cat "$TEST_ROOT/apt.log")" 'Modern fzf must not download scripts'

        fzf_mode=old
        mkdir -p "$target"
        printf 'personal file\n' > "$target/keep"
        status=0
        prepare_fzf_shell_integration || status=$?
        assert_equal 2 "$status" 'Unknown runtime directory is skipped'
        assert_equal 'personal file' "$(cat "$target/keep")" 'Unknown directory contents are preserved'
        assert_equal "$downloaded" "$(cat "$TEST_ROOT/apt.log")" 'Conflicts must not trigger downloads'
        rm -rf "$target"
        package_owner=custom-fzf
        status=0
        prepare_fzf_shell_integration || status=$?
        assert_equal 2 "$status" 'A custom binary must not use another package integration'
        assert_equal "$downloaded" "$(cat "$TEST_ROOT/apt.log")" 'A custom binary must not trigger package downloads'
        package_owner=fzf
        apt_status=100
        status=0
        prepare_fzf_shell_integration || status=$?
        assert_equal 1 "$status" 'APT download failure is reported as a failure'
        [[ ! -e "$target" ]] || fail 'Failed download published runtime scripts'
        [[ -z "$(find "$XDG_DATA_HOME/oh-my-devboom" -mindepth 1 -print)" ]] || fail 'Temporary package files were not cleaned up'
        apt_status=0
        mv() { return 1; }
        status=0
        prepare_fzf_shell_integration || status=$?
        assert_equal 1 "$status" 'Publishing failure is reported as a failure'
        [[ ! -e "$target" ]] || fail 'Failed publication left an incomplete runtime directory'
        [[ -z "$(find "$XDG_DATA_HOME/oh-my-devboom" -mindepth 1 -print)" ]] || fail 'Failed publication left temporary files'
        unset -f mv
        prepare_fzf_shell_integration
        assert_equal '0.44.1 (debian)' "$(cat "$target/fzf-version")" 'Preparation can be retried after a failed publication'
        ;;
    shell)
        if ! command -v zsh >/dev/null 2>&1; then
            printf 'SKIP: shell integration checks require zsh\n'
            exit 0
        fi
        mkdir -p "$TEST_ROOT/fzf" "$XDG_CACHE_HOME/oh-my-devboom"
        # Executables satisfy command detection; Zsh functions below mock their output.
        for tool in fzf zoxide; do
            printf '#!/bin/sh\nexit 99\n' > "$TEST_ROOT/bin/$tool"
            chmod +x "$TEST_ROOT/bin/$tool"
        done
        cat > "$TEST_ROOT/fzf/completion.zsh" <<'ZSH'
fzf-completion() { :; }
zle -N fzf-completion
bindkey '^I' fzf-completion
ZSH
        cat > "$TEST_ROOT/fzf/key-bindings.zsh" <<'ZSH'
(( ++fzf_init_calls ))
fzf-history-widget() { :; }
fzf-file-widget() { :; }
fzf-cd-widget() { :; }
zle -N fzf-history-widget
zle -N fzf-file-widget
zle -N fzf-cd-widget
bindkey '^R' fzf-history-widget
bindkey '^T' fzf-file-widget
bindkey '^[c' fzf-cd-widget
ZSH
        cat > "$TEST_ROOT/check.zsh" <<'ZSH'
set -e
fixture=$1
scenario=$2
# Reproduce Ubuntu's system-level compinit before the user configuration is loaded.
autoload -Uz compinit
compinit -i -d "$fixture/system-zcompdump"
typeset -gi fzf_init_calls=0 zoxide_init_calls=0
fzf() {
    if [[ $1 == --version ]]; then
        print -r -- '0.44.1 (debian)'
        return 0
    fi
    [[ $scenario == modern ]] || return 2
    print -r -- "source '$fixture/fzf/completion.zsh'"
    print -r -- "source '$fixture/fzf/key-bindings.zsh'"
}
zoxide() {
    print -r -- '(( ++zoxide_init_calls )); z() { :; }; zi() { :; }'
}
source "$fixture/zshrc"
[[ $+functions[z] == 1 && $+functions[zi] == 1 && $zoxide_init_calls == 1 ]]
if [[ $scenario != missing_scripts && $scenario != version_mismatch ]]; then
    [[ $fzf_init_calls == 1 ]]
    [[ $(bindkey '^R') == *fzf-history-widget ]]
    [[ $(bindkey '^T') == *fzf-file-widget ]]
    [[ $(bindkey '^[c') == *fzf-cd-widget ]]
    [[ $(bindkey '^I') == *fzf-completion ]]
else
    [[ $fzf_init_calls == 0 ]]
fi
[[ $+functions[_devboom_init_completion] == 0 ]]
ZSH
        cp "$REPO_ROOT/config/zsh/zshrc" "$TEST_ROOT/zshrc"
        fzf_dir="$XDG_DATA_HOME/oh-my-devboom/fzf"
        for scenario in modern old missing_scripts version_mismatch bundle; do
            rm -rf "$fzf_dir"
            case "$scenario" in
                old|version_mismatch|bundle)
                    mkdir -p "$fzf_dir"
                    cp "$TEST_ROOT/fzf/"* "$fzf_dir/"
                    printf '0.44.1 (debian)\n' > "$fzf_dir/fzf-version"
                    if [[ "$scenario" == version_mismatch ]]; then
                        printf '0.43.0 (debian)\n' > "$fzf_dir/fzf-version"
                    fi
                    ;;
            esac
            if [[ "$scenario" == bundle ]]; then
                cat > "$XDG_CACHE_HOME/oh-my-devboom/zsh_plugins.zsh" <<'ZSH'
_devboom_init_completion
# Later plugins must see the widgets already initialized.
[[ $+functions[z] == 1 && $fzf_init_calls == 1 ]] || exit 1
ZSH
            fi
            zsh -dfi "$TEST_ROOT/check.zsh" "$TEST_ROOT" "$scenario" > "$TEST_ROOT/shell.log" 2>&1 || {
                cat "$TEST_ROOT/shell.log" >&2
                fail "Shell integration: $scenario"
            }
            if [[ "$scenario" == missing_scripts || "$scenario" == version_mismatch ]]; then
                [[ $(cat "$TEST_ROOT/shell.log") == *'bootstrap.sh --non-interactive --modules tools --tools fzf'* ]] || fail 'Missing or outdated fzf integration is silent'
            else
                [[ ! -s "$TEST_ROOT/shell.log" ]] || { cat "$TEST_ROOT/shell.log" >&2; fail 'Unexpected shell startup output'; }
            fi
        done
        ;;
    *) fail "Unknown test case: $1" ;;
esac
