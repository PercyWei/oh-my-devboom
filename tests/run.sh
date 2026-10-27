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
    for test_case in detection arguments config idempotency packages remote fzf shell shell_login; do
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
        for module in base homebrew zsh powerlevel10k tools dotfiles shell; do
            [[ "$output" == *"$module"* ]] || fail "Missing module in list: $module"
        done
        [[ "$output" != *starship* ]] || fail 'Removed Starship module is still listed'
        source "$REPO_ROOT/bootstrap.sh"
        parse_args --non-interactive
        assert_equal 'base homebrew zsh powerlevel10k tools dotfiles shell' "$MODULES" 'Default config enables all listed modules, including login shell setup'
        assert_equal 'fzf rg bat eza zoxide nvtop jq fd uv zellij' "$TOOLS" 'Default tools follow the grouped config order'
        assert_equal 'https://ghfast.top/' "$GITHUB_PROXY" 'Default config selects the GitHub download prefix'
        assert_equal 600 "$GIT_TIMEOUT" 'Default Git download timeout is ten minutes'
        parse_args --modules powerlevel10k --non-interactive
        assert_equal powerlevel10k "$MODULES" 'Powerlevel10k module is accepted'
        parse_args --modules shell --non-interactive
        assert_equal shell "$MODULES" 'Login shell setup can be selected independently'
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
        assert_equal '' "$GITHUB_PROXY" 'A custom config without github_proxy uses direct downloads'
        output=$(print_install_plan "$AVAILABLE_MODULES")
        [[ "$output" == *"$config_file"* && "$output" == *'  tools: jq'* ]] || fail 'Plan omits config source or selected tools'
        parse_args --modules dotfiles --tools fd --allow-remote --conflict skip --config "$config_file" --non-interactive
        assert_equal 'dotfiles|fd|1|skip' "$MODULES|$TOOLS|$ALLOW_REMOTE|$CONFLICT_POLICY" 'CLI overrides config when placed before --config'
        parse_args --config "$config_file" --modules dotfiles --tools fd --allow-remote --conflict skip --non-interactive
        assert_equal 'dotfiles|fd|1|skip' "$MODULES|$TOOLS|$ALLOW_REMOTE|$CONFLICT_POLICY" 'CLI overrides config when placed after --config'

        printf '[options]\nallow_remote=true\nconflict=backup\ngithub_proxy=https://proxy.example:8443/prefix/\ngit_timeout=900\n' > "$TEST_ROOT/options.conf"
        parse_args --config "$TEST_ROOT/options.conf" --non-interactive
        assert_equal '||1|backup' "$MODULES|$TOOLS|$ALLOW_REMOTE|$CONFLICT_POLICY" 'Omitted module and tool selections stay empty'
        assert_equal 'https://proxy.example:8443/prefix/' "$GITHUB_PROXY" 'A custom HTTPS prefix may include a port and path'
        assert_equal 900 "$GIT_TIMEOUT" 'Config can change the Git download timeout'
        : > "$TEST_ROOT/empty.conf"
        parse_args --config "$TEST_ROOT/empty.conf" --non-interactive
        assert_equal '||0|skip' "$MODULES|$TOOLS|$ALLOW_REMOTE|$CONFLICT_POLICY" 'Loading another config resets selections and safe options'
        assert_equal '' "$GITHUB_PROXY" 'Loading another config resets the GitHub prefix'
        assert_equal 600 "$GIT_TIMEOUT" 'Loading another config resets the Git download timeout'
        printf '[options]\ngithub_proxy=\n' > "$TEST_ROOT/direct.conf"
        parse_args --config "$TEST_ROOT/direct.conf" --non-interactive
        assert_equal '' "$GITHUB_PROXY" 'An explicit empty prefix selects direct downloads'
        output=$("$BASH_BIN" "$REPO_ROOT/bootstrap.sh" --config "$TEST_ROOT/empty.conf" --non-interactive)
        [[ "$output" == *'未选择安装模块'* ]] || fail 'An empty config should complete without installation'

        for contents in '[unknown]' '[modules]\nunknown=true' '[tools]\nfzf=true\nfzf=false' \
            '[modules]\nbase=yes' '[options]\nconflict=replace' '[modules]\nbase' '[modules]\nbase="true"' \
            '[options]\ngit_timeout=0' '[options]\ngit_timeout=-1' '[options]\ngit_timeout=1.5' '[options]\ngit_timeout='; do
            printf '%b\n' "$contents" > "$TEST_ROOT/invalid.conf"
            if parse_args --config "$TEST_ROOT/invalid.conf" --non-interactive > "$TEST_ROOT/output" 2>&1; then
                fail "Invalid config was accepted: $contents"
            fi
            [[ "$(cat "$TEST_ROOT/output")" == *"$TEST_ROOT/invalid.conf:"* ]] || fail 'Config diagnostics omit the file and line'
        done
        for prefix in 'http://proxy.example/' 'https://proxy.example' 'https:///' \
            'https://user@proxy.example/' 'https://proxy.example/?token=x/' 'https://proxy.example/a b/'; do
            printf '[options]\ngithub_proxy=%s\n' "$prefix" > "$TEST_ROOT/invalid.conf"
            if parse_args --config "$TEST_ROOT/invalid.conf" --non-interactive > "$TEST_ROOT/output" 2>&1; then
                fail "Invalid GitHub prefix was accepted: $prefix"
            fi
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

        printf '[modules]\ndotfiles=true\nshell=false\n[tools]\njq=true\n' > "$config_file"
        parse_args --config "$config_file" --non-interactive
        assert_equal dotfiles "$MODULES" 'shell=false disables login shell changes'
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
        GITHUB_PROXY=''
        GIT_TIMEOUT=37
        # Record and shorten the network timer; retain the one-second cleanup delay.
        sleep() {
            if [[ "$1" != 1 ]]; then
                printf '%s\n' "$1" > "$NETWORK_TEST_DIR/timer-seconds"
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
            assert_equal "$GIT_TIMEOUT" "$(cat "$NETWORK_TEST_DIR/timer-seconds")" 'Git helper uses the configured timer duration'
            case "$NETWORK_SCENARIO" in
                timeout*) [[ "$(cat "$NETWORK_TEST_DIR/output")" == *"Git download timed out after $GIT_TIMEOUT seconds"* ]] || fail 'Git timeout message omits the configured duration' ;;
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
        if command -v script >/dev/null 2>&1 && command -v zsh >/dev/null 2>&1; then
            cat > "$TEST_ROOT/git-tty.sh" <<'FIXTURE'
source "$1/lib/common.sh"
GIT_TIMEOUT=2
GITHUB_PROXY=''
[[ -t 0 ]] || exit 1
parent_trap=$(trap -p TTOU)
status=0
# Antidote uses read -d with heredoc input; Zsh touches the controlling terminal.
run_git_download zsh -f -c 'read -rd "" value <<< "fixture text" || :; kill -s TTOU $$; print -r -- "$value"' \
    > "$2/tty-result" 2> "$2/tty-errors" || status=$?
[[ "$(trap -p TTOU)" == "$parent_trap" ]] || status=1
printf '%s\n' "$status" > "$2/tty-status"
FIXTURE
            tty_platform=$(uname -s)
            case "$tty_platform" in
                Darwin)
                    script -q "$TEST_ROOT/tty-session.log" "$BASH_BIN" "$TEST_ROOT/git-tty.sh" "$REPO_ROOT" "$TEST_ROOT" < /dev/null > /dev/null 2>&1 || :
                    ;;
                Linux)
                    printf -v tty_command '%q ' "$BASH_BIN" "$TEST_ROOT/git-tty.sh" "$REPO_ROOT" "$TEST_ROOT"
                    SHELL="$BASH_BIN" script -q -c "$tty_command" "$TEST_ROOT/tty-session.log" < /dev/null > /dev/null 2>&1 || :
                    ;;
                *) printf 'SKIP: real TTY check supports macOS and Linux script\n' ;;
            esac
            case "$tty_platform" in
                Darwin|Linux)
                    assert_equal 0 "$(cat "$TEST_ROOT/tty-status")" 'Background Zsh must not stop on terminal access'
                    assert_equal 'fixture text' "$(cat "$TEST_ROOT/tty-result")" 'Child Zsh reads heredoc input and inherits ignored SIGTTOU'
                    ;;
            esac
        else
            printf 'SKIP: real TTY check requires script and zsh\n'
        fi
        export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=devboom.fixture GIT_CONFIG_VALUE_0=preserved
        GITHUB_PROXY=https://proxy.example/
        run_git_download "$BASH_BIN" -c '
            printf "%s\n" "$GIT_CONFIG_COUNT" > "$1/git-config-count"
            git config --get devboom.fixture > "$1/git-config-existing"
            git ls-remote --get-url https://github.com/example/repo.git > "$1/git-url"
        ' fixture "$TEST_ROOT"
        assert_equal 2 "$(cat "$TEST_ROOT/git-config-count")" 'Git prefix appends one runtime config entry'
        assert_equal preserved "$(cat "$TEST_ROOT/git-config-existing")" 'Child Git retains the existing runtime config'
        assert_equal 'https://proxy.example/https://github.com/example/repo.git' "$(cat "$TEST_ROOT/git-url")" 'Nested Git commands inherit the URL rewrite without network access'
        assert_equal '1|devboom.fixture|preserved' "$GIT_CONFIG_COUNT|$GIT_CONFIG_KEY_0|$GIT_CONFIG_VALUE_0" 'Git helper preserves the parent runtime config'
        [[ -z "${GIT_CONFIG_KEY_1-}" && -z "${GIT_CONFIG_VALUE_1-}" && ! -e "$HOME/.gitconfig" ]] || fail 'Git prefix leaked to the parent or a config file'
        GIT_CONFIG_KEY_0=url.https://other.example/https://github.com/.insteadOf
        GIT_CONFIG_VALUE_0=https://github.com/
        status=0
        run_git_download touch "$TEST_ROOT/conflicting-rewrite-executed" > "$TEST_ROOT/git-conflict.log" 2>&1 || status=$?
        assert_equal 1 "$status" 'A competing Git rewrite is reported as a failure'
        [[ ! -e "$TEST_ROOT/conflicting-rewrite-executed" ]] || fail 'Git helper executed a command with the wrong download prefix'
        GIT_CONFIG_KEY_0=devboom.fixture
        GIT_CONFIG_VALUE_0=preserved
        GITHUB_PROXY=''
        run_git_download git ls-remote --get-url https://github.com/example/repo.git > "$TEST_ROOT/git-url"
        assert_equal 'https://github.com/example/repo.git' "$(cat "$TEST_ROOT/git-url")" 'An empty prefix keeps Git downloads direct'
        unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
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
        wget() { printf '%s\n' "$*" > "$TEST_ROOT/downloader.args"; }
        for downloader in curl wget; do
            have() { [[ "$1" == "$downloader" ]]; }
            GITHUB_PROXY=https://proxy.example/
            for url in https://github.com/example/repo/releases/archive.tar.gz \
                https://raw.githubusercontent.com/example/repo/main/install.sh \
                https://astral.sh/uv/install.sh https://github.com.example.invalid/file \
                https://proxy.example/https://github.com/example/repo/archive.tar.gz; do
                case "$url" in
                    https://github.com/*|https://raw.githubusercontent.com/*) expected="$GITHUB_PROXY$url" ;;
                    *) expected=$url ;;
                esac
                output=$(download_file "$url" "$TEST_ROOT/download")
                args=$(cat "$TEST_ROOT/downloader.args")
                [[ "$args" == *" $expected" ]] || fail "$downloader routed the wrong URL: $url"
                if [[ "$expected" != "$url" ]]; then
                    [[ "$output" == *"$url"* && "$output" == *"$expected"* ]] || fail 'Download log omits the official or actual URL'
                fi
            done
            GITHUB_PROXY=''
            download_file https://github.com/example/repo/archive.tar.gz "$TEST_ROOT/download"
            args=$(cat "$TEST_ROOT/downloader.args")
            [[ "$args" == *' https://github.com/example/repo/archive.tar.gz' ]] || fail "$downloader ignored the direct-download setting"
        done
        have() { [[ "$1" == curl ]]; }
        curl() { printf '%s\n' "$*" >> "$TEST_ROOT/failed-download.args"; return 28; }
        GITHUB_PROXY=https://proxy.example/
        status=0
        download_file https://github.com/example/repo/archive.tar.gz "$TEST_ROOT/download" || status=$?
        assert_equal 1 "$status" 'A proxy download failure remains a failure'
        args=$(cat "$TEST_ROOT/failed-download.args")
        [[ "$args" != *$'\n'* && "$args" == *' https://proxy.example/https://github.com/example/repo/archive.tar.gz' ]] || fail 'A failed proxy request retried outside the configured prefix'
        GITHUB_PROXY=''
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
    shell_login)
        source "$REPO_ROOT/lib/common.sh"
        source "$REPO_ROOT/lib/packages.sh"
        source "$REPO_ROOT/modules/shell.sh"
        target="$TEST_ROOT/bin/zsh"
        account_file="$TEST_ROOT/account-shell"
        SHELLS_FILE="$TEST_ROOT/shells"
        # Even a command-prefixed invocation must never reach the host's chsh/sudo.
        for tool in zsh chsh sudo; do
            printf '#!/bin/sh\nexit 99\n' > "$TEST_ROOT/bin/$tool"
            chmod +x "$TEST_ROOT/bin/$tool"
        done
        printf '# Registered shells\n/bin/bash\n%s\n' "$target" > "$SHELLS_FILE"
        : > "$TEST_ROOT/chsh.log"
        : > "$TEST_ROOT/sudo.log"
        id() {
            case "$1" in
                -u) printf '%s\n' "$USER_ID" ;;
                -un) printf 'fixture\n' ;;
                *) fail "Unexpected id invocation: $*" ;;
            esac
        }
        getent() {
            [[ "$OS" == linux ]] || fail 'macOS queried the Linux account database'
            assert_equal "passwd $USER_ID" "$*" 'Linux queries the current UID'
            printf 'fixture:x:%s:123:Fixture:%s:%s\n' "$USER_ID" "$HOME" "$(cat "$account_file")"
        }
        dscl() {
            assert_equal '. -read /Users/fixture UserShell' "$*" 'macOS reads the current account UserShell'
            printf 'UserShell: %s\n' "$(cat "$account_file")"
        }
        chsh() {
            assert_equal "-s $target fixture" "$*" 'chsh targets the registered shell and current account'
            printf '%s\n' "$*" >> "$TEST_ROOT/chsh.log"
            case "$chsh_mode" in
                fail) return 7 ;;
                no_change) return 0 ;;
                *) printf '%s\n' "$2" > "$account_file" ;;
            esac
        }
        sudo() {
            printf '%s\n' "$*" >> "$TEST_ROOT/sudo.log"
            [[ "$1" == -n ]] || fail 'Non-interactive shell changes invoked interactive sudo'
            shift
            if [[ "$*" == true ]]; then return "$sudo_status"; fi
            [[ "$1" == chsh ]] || fail "Unexpected sudo command: $*"
            "$@"
        }
        OS=linux
        USER_ID=0
        HAS_SUDO=0
        INTERACTIVE=0
        chsh_mode=change
        sudo_status=0
        printf '%s\n' "$target" > "$account_file"
        printf '/bin/bash\n' > "$SHELLS_FILE"
        module_shell
        [[ ! -s "$TEST_ROOT/chsh.log" ]] || fail 'An existing Zsh login shell was changed'
        printf '%s\n' "$target" > "$SHELLS_FILE"

        for scenario in root interactive sudo; do
            USER_ID=4242 HAS_SUDO=0 INTERACTIVE=0
            case "$scenario" in
                root) USER_ID=0 ;;
                interactive) INTERACTIVE=1 ;;
                sudo) HAS_SUDO=1 ;;
            esac
            printf '/bin/bash\n' > "$account_file"
            : > "$TEST_ROOT/chsh.log"
            : > "$TEST_ROOT/sudo.log"
            module_shell
            assert_equal "$target" "$(cat "$account_file")" "$scenario updates the fixture login shell"
            assert_equal "-s $target fixture" "$(cat "$TEST_ROOT/chsh.log")" "$scenario changes the account exactly once"
            if [[ "$scenario" == sudo ]]; then
                assert_equal "$(printf '%s\n' '-n true' "-n chsh -s $target fixture")" "$(cat "$TEST_ROOT/sudo.log")" 'Non-interactive sudo is probed and invoked with -n'
            else
                [[ ! -s "$TEST_ROOT/sudo.log" ]] || fail "$scenario unnecessarily invoked sudo"
            fi
        done
        module_shell
        assert_equal "-s $target fixture" "$(cat "$TEST_ROOT/chsh.log")" 'Repeated shell setup does not run chsh again'

        printf '/bin/bash\n' > "$account_file"
        : > "$TEST_ROOT/chsh.log"
        sudo_status=1
        for HAS_SUDO in 0 1; do
            status=0
            module_shell || status=$?
            assert_equal 2 "$status" 'Missing non-interactive privilege reports a skip'
        done
        [[ ! -s "$TEST_ROOT/chsh.log" ]] || fail 'Unavailable sudo still invoked chsh'
        USER_ID=0
        printf '/bin/bash\n' > "$SHELLS_FILE"
        status=0
        module_shell || status=$?
        assert_equal 2 "$status" 'No registered executable Zsh reports a skip'
        [[ ! -s "$TEST_ROOT/chsh.log" ]] || fail 'An unregistered shell reached chsh'
        printf '%s\n' "$target" > "$SHELLS_FILE"
        for chsh_mode in fail no_change; do
            status=0
            module_shell || status=$?
            assert_equal 1 "$status" 'chsh failure or an unchanged account reports failure'
            assert_equal /bin/bash "$(cat "$account_file")" 'Failed shell setup preserves the original fixture shell'
        done
        OS=macos USER_ID=501 INTERACTIVE=1 HAS_SUDO=0 chsh_mode=change
        module_shell
        assert_equal "$target" "$(cat "$account_file")" 'macOS reads and confirms the shell through dscl'
        ;;
    *) fail "Unknown test case: $1" ;;
esac
