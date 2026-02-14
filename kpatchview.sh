#!/usr/bin/env bash
set -euo pipefail

usage() {
        cat <<'EOF'
Usage: kpatchview [OPTION]...
View patch files and Git diffs using Vim/Vimdiff.

Options:
    inline <patch-file>            open patch in inline mode (read-only)
    ss/side-by-side <patch-file>   open patch in side-by-side mode (default)
    gd/git-diff [args...]          open git diff in side-by-side mode
    gs/git-show [args...]          open git show in side-by-side mode

    -h, --help                    display this help and exit
EOF
}

require_file() {
        local file="$1"
        if [[ ! -f "$file" ]]; then
                echo "Error: file not found: $file" >&2
                exit 1
        fi
}

term_cols() {
        tput cols 2>/dev/null || echo 120
}

clamp_min() {
        local value="$1"
        local min="$2"
        if ((value < min)); then
                value="$min"
        fi
        echo "$value"
}

calc_pane_width() {
        local cols
        local pane_width
        cols="$(term_cols)"
        pane_width=$((cols / 2))
        pane_width="$(clamp_min "$pane_width" 20)"
        echo "$pane_width"
}

calc_box_width() {
        local pane_width
        local width
        pane_width="$(calc_pane_width)"
        width=$((pane_width * 90 / 100))
        width="$(clamp_min "$width" 20)"
        echo "$width"
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
        printf '\n%s\n%s\n\n' "$title" "$line"
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

open_vimdiff_with_summary() {
        local summary_file="$1"
        local vimcmds="$WORKDIR/vimcmds.vim"
        cat >"$vimcmds" <<'VIM'
set shortmess+=FI
set nofoldenable
windo set nofoldenable
function! KpatchTabLine()
  let s=""
  for i in range(tabpagenr("$"))
    let tab=i+1
    let winnr=tabpagewinnr(tab)
    let buf=tabpagebuflist(tab)[winnr-1]
    let label=bufname(buf)
    if label==""
      let label="[No Name]"
    endif
    let hl=(tab==tabpagenr())?"%#TabLineSel#":"%#TabLine#"
    let s.=hl." ".label." "
  endfor
  let s.="%#TabLineFill#"
  return s
endfunction
set tabline=%!KpatchTabLine()
file FileChanges
VIM
        printf 'tabnew %s\nfile Summary\nsetlocal filetype=git\ntabfirst\n' "$summary_file" >>"$vimcmds"
        vim -d -R -S "$vimcmds" -- "$LEFT_PANE" "$RIGHT_PANE" </dev/tty
}

render_unified_to_panes() {
        local left="$1"
        local right="$2"
        local box_width="$3"

        awk -v left="$left" -v right="$right" -v box_width="$box_width" '
                BEGIN {
                        in_diff = 0
                        collecting = 0
                        saw_sep = 0
                        header = ""
                }
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
                function print_blank_pair(count,    i) {
                        for (i = 0; i < count; i++) {
                                print "" >> left
                                print "" >> right
                        }
                }
                function flush_header() {
                        if (collecting && saw_sep) {
                                print_blank_pair(2)
                                printf "%s\n", header >> left
                                printf "%s\n", header >> right
                                header = ""
                                collecting = 0
                                saw_sep = 0
                        }
                }
                /^diff --git / {
                        flush_header()
                        in_diff = 1
                        next
                }
                !in_diff {
                        if (!collecting && $0 ~ /^From [0-9a-f]{7,40} /) {
                                collecting = 1
                        } else if (!collecting && $0 ~ /^From:[[:space:]]+/) {
                                collecting = 1
                        }
                        if (collecting) {
                                header = header $0 "\n"
                                if ($0 == "---") {
                                        saw_sep = 1
                                } else if (saw_sep && $0 == "") {
                                        flush_header()
                                }
                        }
                        next
                }
                /^index / { next }
                /^--- / { old = $2; next }
                /^\+\+\+ / {
                        file = $2
                        if (file == "/dev/null") { file = old }
                        file = clean(file)
                        file = "File | " file
                        print_blank_pair(1)
                        print_box(left, file, box_width)
                        print_box(right, file, box_width)
                        print_blank_pair(1)
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

        open_vimdiff_with_summary "$summary"
}

mode="${1:-}"
case "$mode" in
        inline)
                [[ $# -eq 2 ]] || { usage; exit 2; }
                inline_patch "$2"
                ;;
        side-by-side|ss)
                [[ $# -eq 2 ]] || { usage; exit 2; }
                side_by_side_patch "$2"
                ;;
        git-diff|gd)
                shift
                git_diff_inline "$@"
                ;;
        git-show|gs)
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
