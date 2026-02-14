# KpatchView

KpatchView is a lightweight Vim/Vimdiff-based viewer that provides a git-delta-like workflow for patch files and Git diffs.

## Features

- Inline patch view
- Side-by-side patch view
- Side-by-side view of `git diff` and `git show`

## Requirements

- Bash
- Vim with diff support (vimdiff)
- Git

## Install

```bash
make install
```

## Usage

### Patch files

Inline view:

```bash
kpatchview inline /path/to/patch.diff
```

Side-by-side view:

```bash
kpatchview side-by-side /path/to/patch.diff
kpatchview ss /path/to/patch.diff
```

Default behavior (side-by-side):

```bash
kpatchview /path/to/patch.diff
```

### Git integration

Side-by-side diff:

```bash
kpatchview git-diff
kpatchview gd
```

Side-by-side show:

```bash
kpatchview git-show
kpatchview gs
```

You can pass any normal arguments to Git:

```bash
kpatchview git-diff --stat
kpatchview git-show HEAD~1..HEAD
```

### Hook into Git

#### Option 1: Git aliases (recommended)

```bash
git config --global alias.vimdiff '!kpatchview git-diff'
git config --global alias.vimshow '!kpatchview git-show'
```

Usage:

```bash
git vimdiff
git vimshow HEAD~1..HEAD
```

#### Option 2: Pager override

```bash
git config --global pager.diff 'kpatchview git-diff'
git config --global pager.show 'kpatchview git-show'
```

## Behavior

- Read-only mode is enforced for all views
- File headers with the label `File | <name>`
- git show prepends a summary (--stat --summary) above the diff in both panes
- Vim reads input from /dev/tty to work as a Git pager

## Limitations

- Very large diffs may be slow in Vimdiff.
- Side-by-side view reconstructs panes from unified diff output; it is best-effort.

---
