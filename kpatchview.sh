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

render_header() {
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

write_header() {
        render_header "$@"
}

make_title() {
        local label="$1"
        shift
        if (( $# > 0 )); then
                echo "$label ($*)"
        else
                echo "$label"
        fi
}

init_panes() {
        local title="$1"
        local pane_width="$2"
        local left="$3"
        local right="$4"
        local header
        header="$(render_header "$title" "$pane_width")"
        HEADER_LINE_COUNT=$(printf '%s' "$header" | wc -l)
        if [[ -n "${HEADER_LINE_COUNT_OVERRIDE:-}" ]]; then
                HEADER_LINE_COUNT="$HEADER_LINE_COUNT_OVERRIDE"
        fi
        printf '%s' "$header" >"$left"
        printf '%s' "$header" >"$right"
}

init_workspace() {
        local title="$1"
        declare -g WORKDIR
        declare -g LEFT_PANE
        declare -g RIGHT_PANE
        declare -g BOX_WIDTH
        declare -g PANE_WIDTH
        declare -g HEADER_LINE_COUNT
        WORKDIR="$(mktemp -d)"
        LEFT_PANE="$WORKDIR/left"
        RIGHT_PANE="$WORKDIR/right"
        BOX_WIDTH="$(calc_box_width)"
        PANE_WIDTH="$(calc_pane_width)"
        trap '[[ -n "${WORKDIR:-}" ]] && rm -rf "$WORKDIR"' EXIT
        init_panes "$title" "$PANE_WIDTH" "$LEFT_PANE" "$RIGHT_PANE"
}

open_vimdiff() {
        vim -d -R -c 'set shortmess+=FI' -c 'set nofoldenable' -c 'windo set nofoldenable' \
                -- "$LEFT_PANE" "$RIGHT_PANE" </dev/tty
}

insert_summary_after_header() {
        local summary_file="$1"
        local pane_file="$2"
        local out_file="$3"
        local tail_start=$((HEADER_LINE_COUNT + 1))
        {
                head -n "$HEADER_LINE_COUNT" "$pane_file"
                cat "$summary_file"
                echo
                tail -n +"$tail_start" "$pane_file"
        } >"$out_file"
}

render_unified_to_panes() {
        local left="$1"
        local right="$2"
        local box_width="$3"

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
        '
}

inline_patch() {
        local patch="$1"
        require_file "$patch"
        vim -R -c 'set shortmess+=FI' -c 'set nofoldenable' -c 'set filetype=diff' -- "$patch" </dev/tty
}

side_by_side_patch() {
        local patch="$1"
        require_file "$patch"
        local title
        title="PATCHVIEW ($patch)"

        init_workspace "$title"
        render_unified_to_panes "$LEFT_PANE" "$RIGHT_PANE" "$BOX_WIDTH" <"$patch"
        open_vimdiff
}

git_diff_inline() {
        local title
        title="$(make_title "GIT DIFF" "$@")"

        init_workspace "$title"
        git diff "$@" | render_unified_to_panes "$LEFT_PANE" "$RIGHT_PANE" "$BOX_WIDTH"
        open_vimdiff
}

git_show_inline() {
        local title
        title="$(make_title "GIT SHOW" "$@")"

        init_workspace "$title"
        local summary="$WORKDIR/summary"
        : >"$summary"

        git show "$@" | render_unified_to_panes "$LEFT_PANE" "$RIGHT_PANE" "$BOX_WIDTH"
        git show --no-patch --stat --summary "$@" >"$summary"

        if [[ -s "$summary" ]]; then
                insert_summary_after_header "$summary" "$LEFT_PANE" "$WORKDIR/left.tmp" && mv "$WORKDIR/left.tmp" "$LEFT_PANE"
                insert_summary_after_header "$summary" "$RIGHT_PANE" "$WORKDIR/right.tmp" && mv "$WORKDIR/right.tmp" "$RIGHT_PANE"
        fi

        open_vimdiff
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
