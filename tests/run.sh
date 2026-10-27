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
    for test_case in detection arguments config idempotency packages remote shell; do
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
        [[ "$output" == *--modules* && "$output" == *--allow-remote* ]] || fail 'Help documents module and remote options'
        output=$("$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --list-modules)
        for module in base homebrew zsh powerlevel10k tools dotfiles; do
            [[ "$output" == *"$module"* ]] || fail "Missing module in list: $module"
        done
        [[ "$output" != *starship* ]] || fail 'Removed Starship module is still listed'
        source "$REPO_ROOT/bootstrap.sh"
        parse_args --yes
        assert_equal 'base homebrew zsh powerlevel10k dotfiles' "$MODULES" 'Default modules include Powerlevel10k'
        assert_equal 'uv fzf rg bat eza zoxide zellij nvtop jq fd' "$TOOLS" 'Default tools include Zellij, nvtop, jq and fd'
        parse_args --modules powerlevel10k --yes
        assert_equal powerlevel10k "$MODULES" 'Powerlevel10k module is accepted'
        parse_args --modules tools --tools zellij,nvtop,jq,fd --yes
        assert_equal 'zellij nvtop jq fd' "$TOOLS" 'Zellij, nvtop, jq and fd are accepted tools'
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --yes --unknown > "$TEST_ROOT/output" 2>&1; then
            fail 'Unknown option was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules unknown --yes > "$TEST_ROOT/output" 2>&1; then
            fail 'Unknown module was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules starship --yes > "$TEST_ROOT/output" 2>&1; then
            fail 'Removed Starship module was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --tools unknown --yes > "$TEST_ROOT/output" 2>&1; then
            fail 'Unknown tool was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --conflict replace --yes > "$TEST_ROOT/output" 2>&1; then
            fail 'Unknown conflict policy was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules > "$TEST_ROOT/output" 2>&1; then
            fail 'Missing option value was accepted'
        fi
        if "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles < /dev/null > "$TEST_ROOT/output" 2>&1; then
            fail 'Non-interactive execution without --yes was accepted'
        fi
        [[ ! -e "$HOME/.zshrc" && ! -e "$HOME/.gitconfig" ]] || fail 'Argument checks changed HOME'
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

        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --yes > "$TEST_ROOT/first-run.log" 2>&1 || { cat "$TEST_ROOT/first-run.log" >&2; fail 'First dotfiles run failed'; }
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --yes > "$TEST_ROOT/second-run.log" 2>&1 || { cat "$TEST_ROOT/second-run.log" >&2; fail 'Second dotfiles run failed'; }
        [[ -L "$HOME/.zshrc" ]] || fail 'Dotfiles module did not deploy .zshrc'
        [[ -L "$HOME/.gitconfig" ]] || fail 'Dotfiles module did not deploy .gitconfig'
        [[ -L "$HOME/.p10k.zsh" ]] || fail 'Dotfiles module did not deploy .p10k.zsh'
        assert_equal "$REPO_ROOT/config/powerlevel10k/p10k.zsh" "$(readlink "$HOME/.p10k.zsh")" 'Powerlevel10k preset source'
        [[ -z "$(find "$HOME" -name '*.backup.*' ! -path "$HOME/existing.backup.*" -print)" ]] || fail 'Repeated CLI deployment made unexpected backups'

        export ZDOTDIR="$HOME/custom-zsh"
        mkdir -p "$ZDOTDIR"
        printf 'personal prompt\n' > "$ZDOTDIR/.p10k.zsh"
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --yes > "$TEST_ROOT/skip-run.log" 2>&1 || { cat "$TEST_ROOT/skip-run.log" >&2; fail 'Dotfiles skip run failed'; }
        [[ -L "$ZDOTDIR/.zshrc" ]] || fail 'Dotfiles module did not respect ZDOTDIR for .zshrc'
        [[ ! -L "$ZDOTDIR/.p10k.zsh" ]] || fail 'Default skip policy replaced a personal Powerlevel10k preset'
        assert_equal 'personal prompt' "$(cat "$ZDOTDIR/.p10k.zsh")" 'Skipped Powerlevel10k preset is preserved'
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --yes --conflict backup > "$TEST_ROOT/backup-run.log" 2>&1 || { cat "$TEST_ROOT/backup-run.log" >&2; fail 'Dotfiles backup run failed'; }
        "$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --modules dotfiles --yes --conflict backup > "$TEST_ROOT/repeated-backup-run.log" 2>&1 || { cat "$TEST_ROOT/repeated-backup-run.log" >&2; fail 'Repeated dotfiles backup run failed'; }
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
            " $args " == *' --retry 2 '* && " $args " == *' --retry-max-time 300 '* ]] || fail 'Curl download limits are missing'
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
    [[ $scenario == modern || $scenario == bundle ]] || return 2
    print -r -- "source '$fixture/fzf/completion.zsh'"
    print -r -- "source '$fixture/fzf/key-bindings.zsh'"
}
zoxide() {
    print -r -- '(( ++zoxide_init_calls )); z() { :; }; zi() { :; }'
}
source "$fixture/zshrc"
[[ $+functions[z] == 1 && $+functions[zi] == 1 && $zoxide_init_calls == 1 ]]
if [[ $scenario != missing_scripts ]]; then
    [[ $fzf_init_calls == 1 ]]
    [[ $(bindkey '^R') == *fzf-history-widget ]]
    [[ $(bindkey '^T') == *fzf-file-widget ]]
    [[ $(bindkey '^[c') == *fzf-cd-widget ]]
    [[ $(bindkey '^I') == *fzf-completion ]]
fi
[[ $+functions[_devboom_init_completion] == 0 ]]
ZSH
        for scenario in modern old missing_scripts bundle; do
            fixture_dir="$TEST_ROOT/fzf"
            if [[ "$scenario" == missing_scripts ]]; then fixture_dir="$TEST_ROOT/missing"; fi
            # Redirect only the system package's file paths into the isolated fixture.
            sed "s|/usr/share/doc/fzf/examples|$fixture_dir|g" "$REPO_ROOT/config/zsh/zshrc" > "$TEST_ROOT/zshrc"
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
            if [[ "$scenario" == missing_scripts ]]; then
                [[ $(cat "$TEST_ROOT/shell.log") == *'请升级 fzf'* ]] || fail 'Missing fzf integration is silent'
            else
                [[ ! -s "$TEST_ROOT/shell.log" ]] || { cat "$TEST_ROOT/shell.log" >&2; fail 'Unexpected shell startup output'; }
            fi
        done
        ;;
    *) fail "Unknown test case: $1" ;;
esac
