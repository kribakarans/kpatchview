#!/usr/bin/env bash
set -euo pipefail

usage() {
        cat <<'EOF'
Usage: kpatchview [OPTION]...
View patch files and Git diffs using Vim/Vimdiff.

Options:
    inline <patch-file>         open patch in inline mode (read-only)
    side-by-side <patch-file>   open patch in side-by-side mode (default)
    git-diff [args...]          open git diff in side-by-side mode
    git-show [args...]          open git show in side-by-side mode

    -h, --help                  display this help and exit
EOF
}

require_file() {
        local file="$1"
        if [[ ! -f "$file" ]]; then
                echo "Error: file not found: $file" >&2
                exit 1
        fi
}

calc_box_width() {
        local cols
        cols="$(tput cols 2>/dev/null || echo 120)"
        local pane_width=$((cols / 2))
        local width=$((pane_width * 90 / 100))
        if ((width < 20)); then
                width=20
        fi
        echo "$width"
}

calc_pane_width() {
        local cols
        cols="$(tput cols 2>/dev/null || echo 120)"
        local pane_width=$((cols / 2))
        if ((pane_width < 20)); then
                pane_width=20
        fi
        echo "$pane_width"
}

write_header() {
        local title="$1"
        local pane_width="$2"
        local line_width=$((pane_width * 90 / 100))
        local line
        if ((line_width < 20)); then
                line_width=20
        fi
        line="$(printf '%*s' "$line_width" '' | tr ' ' '_')"
        printf '\n%s\n%s\n' "$title" "$line"
}

inline_patch() {
        local patch="$1"
        require_file "$patch"
        vim -R -c 'set shortmess+=FI' -c 'set nofoldenable' -c 'set filetype=diff' -- "$patch" </dev/tty
}

side_by_side_patch() {
        local patch="$1"
        require_file "$patch"

        local tmpdir
        tmpdir="$(mktemp -d)"
        local left="$tmpdir/left"
        local right="$tmpdir/right"
        local box_width
        box_width="$(calc_box_width)"
        local pane_width
        pane_width="$(calc_pane_width)"
        local title
        title="PATCHVIEW ($patch)"
        trap '[[ -n "${tmpdir:-}" ]] && rm -rf "$tmpdir"' EXIT

        write_header "$title" "$pane_width" >"$left"
        write_header "$title" "$pane_width" >"$right"

        awk -v left="$left" -v right="$right" -v box_width="$box_width" '
                function clean(path) {
                        sub(/^a\//, "", path)
                        sub(/^b\//, "", path)
                        return path
                }
                function repeat(ch, len,    i, line) {
                        line = ""
                        for (i = 0; i < len; i++) {
                                line = line ch
                        }
                        return line
                }
                function print_box(dest, name, width,    max, pad, top, mid, bot) {
                        if (width < 4) {
                                width = 4
                        }
                        max = width - 4
                        if (length(name) > max) {
                                name = substr(name, 1, max - 3) "..."
                        }
                        pad = max - length(name)
                        top = "┏" repeat("━", width - 2) "┓"
                        mid = "┃ " name repeat(" ", pad) " ┃"
                        bot = "┗" repeat("━", width - 2) "┛"
                        print top >> dest
                        print mid >> dest
                        print bot >> dest
                }
                /^diff --git / { next }
                /^index / { next }
                /^--- / { old = $2; next }
                /^\+\+\+ / {
                        file = $2
                        if (file == "/dev/null") { file = old }
                        file = clean(file)
                        file = "File | " file
                        print "" >> left
                        print "" >> right
                        print_box(left, file, box_width)
                        print_box(right, file, box_width)
                        print "" >> left
                        print "" >> right
                        next
                }
                /^@@/ { next }
                /^\\ No newline at end of file/ { next }
                /^-/ { print substr($0, 2) >> left; next }
                /^\+/ { print substr($0, 2) >> right; next }
                /^ / { line = substr($0, 2); print line >> left; print line >> right; next }
                { next }
        ' "$patch"

        vim -d -R -c 'set shortmess+=FI' -c 'set nofoldenable' -c 'windo set nofoldenable' -- "$left" "$right" </dev/tty
}

git_diff_inline() {
        local tmpdir
        tmpdir="$(mktemp -d)"
        local left="$tmpdir/left"
        local right="$tmpdir/right"
        local box_width
        box_width="$(calc_box_width)"
        local pane_width
        pane_width="$(calc_pane_width)"
        local title
        if (( $# > 0 )); then
                title="GIT DIFF ($*)"
        else
                title="GIT DIFF"
        fi
        trap '[[ -n "${tmpdir:-}" ]] && rm -rf "$tmpdir"' EXIT

        write_header "$title" "$pane_width" >"$left"
        write_header "$title" "$pane_width" >"$right"

        git diff "$@" | awk -v left="$left" -v right="$right" -v box_width="$box_width" '
                function clean(path) {
                        sub(/^a\//, "", path)
                        sub(/^b\//, "", path)
                        return path
                }
                function repeat(ch, len,    i, line) {
                        line = ""
                        for (i = 0; i < len; i++) {
                                line = line ch
                        }
                        return line
                }
                function print_box(dest, name, width,    max, pad, top, mid, bot) {
                        if (width < 4) {
                                width = 4
                        }
                        max = width - 4
                        if (length(name) > max) {
                                name = substr(name, 1, max - 3) "..."
                        }
                        pad = max - length(name)
                        top = "┏" repeat("━", width - 2) "┓"
                        mid = "┃ " name repeat(" ", pad) " ┃"
                        bot = "┗" repeat("━", width - 2) "┛"
                        print top >> dest
                        print mid >> dest
                        print bot >> dest
                }
                /^diff --git / { next }
                /^index / { next }
                /^--- / { old = $2; next }
                /^\+\+\+ / {
                        file = $2
                        if (file == "/dev/null") { file = old }
                        file = clean(file)
                        file = "File | " file
                        print "" >> left
                        print "" >> right
                        print_box(left, file, box_width)
                        print_box(right, file, box_width)
                        print "" >> left
                        print "" >> right
                        next
                }
                /^@@/ { next }
                /^\\ No newline at end of file/ { next }
                /^-/ { print substr($0, 2) >> left; next }
                /^\+/ { print substr($0, 2) >> right; next }
                /^ / { line = substr($0, 2); print line >> left; print line >> right; next }
                { next }
        '

        vim -d -R -c 'set shortmess+=FI' -c 'set nofoldenable' -c 'windo set nofoldenable' -- "$left" "$right" </dev/tty
}

git_show_inline() {
        local tmpdir
        tmpdir="$(mktemp -d)"
        local left="$tmpdir/left"
        local right="$tmpdir/right"
        local summary="$tmpdir/summary"
        local box_width
        box_width="$(calc_box_width)"
        local pane_width
        pane_width="$(calc_pane_width)"
        local title
        if (( $# > 0 )); then
                title="GIT SHOW ($*)"
        else
                title="GIT SHOW"
        fi
        trap '[[ -n "${tmpdir:-}" ]] && rm -rf "$tmpdir"' EXIT

        write_header "$title" "$pane_width" >"$left"
        write_header "$title" "$pane_width" >"$right"
        : >"$summary"

        git show "$@" | awk -v left="$left" -v right="$right" -v box_width="$box_width" -v summary="$summary" '
                function clean(path) {
                        sub(/^a\//, "", path)
                        sub(/^b\//, "", path)
                        return path
                }
                function repeat(ch, len,    i, line) {
                        line = ""
                        for (i = 0; i < len; i++) {
                                line = line ch
                        }
                        return line
                }
                function print_box(dest, name, width,    max, pad, top, mid, bot) {
                        if (width < 4) {
                                width = 4
                        }
                        max = width - 4
                        if (length(name) > max) {
                                name = substr(name, 1, max - 3) "..."
                        }
                        pad = max - length(name)
                        top = "┏" repeat("━", width - 2) "┓"
                        mid = "┃ " name repeat(" ", pad) " ┃"
                        bot = "┗" repeat("━", width - 2) "┛"
                        print top >> dest
                        print mid >> dest
                        print bot >> dest
                }
                /^diff --git / { next }
                /^index / { next }
                /^--- / { old = $2; next }
                /^\+\+\+ / {
                        file = $2
                        if (file == "/dev/null") { file = old }
                        file = clean(file)
                        file = "File | " file
                        print "" >> left
                        print "" >> right
                        print_box(left, file, box_width)
                        print_box(right, file, box_width)
                        print "" >> left
                        print "" >> right
                        next
                }
                /^@@/ { next }
                /^\\ No newline at end of file/ { next }
                /^-/ { print substr($0, 2) >> left; next }
                /^\+/ { print substr($0, 2) >> right; next }
                /^ / { line = substr($0, 2); print line >> left; print line >> right; next }
                { next }
        '

        git show --no-patch --stat --summary "$@" >"$summary"

        if [[ -s "$summary" ]]; then
                {
                        cat "$summary"
                        echo
                } | cat - "$left" >"$left.tmp" && mv "$left.tmp" "$left"
                {
                        cat "$summary"
                        echo
                } | cat - "$right" >"$right.tmp" && mv "$right.tmp" "$right"
        fi

        vim -d -R \
                -c 'set shortmess+=FI' \
                -c 'set nofoldenable' \
                -c 'windo set nofoldenable' \
                -c 'file FileChanges' \
                -- "$left" "$right" </dev/tty
}

mode="${1:-}"
case "$mode" in
        inline)
                [[ $# -eq 2 ]] || { usage; exit 2; }
                inline_patch "$2"
                ;;
        side-by-side)
                [[ $# -eq 2 ]] || { usage; exit 2; }
                side_by_side_patch "$2"
                ;;
        git-diff)
                shift
                git_diff_inline "$@"
                ;;
        git-show)
                shift
                git_show_inline "$@"
                ;;
        -h|--help|help)
                usage
                ;;
        *)
                if [[ -n "$mode" && -f "$mode" ]]; then
                        side_by_side_patch "$mode"
                else
                        echo "Oops! missing file operand" >&2
                        exit 2
                fi
                ;;
esac
