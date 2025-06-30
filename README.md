# makecmd

Convert natural language to shell commands using Claude.

## What it does

Type what you want in plain English, get back a shell command:

```bash
$ makecmd "find all large files"
find . -type f -size +100M

$ makecmd "show disk usage"  
df -h

$ makecmd "count python files"
find . -name "*.py" | wc -l
```

## Installation

Prerequisites:
- [Claude Code](https://claude.ai/code) installed
- Bash 3.2+

Install:
```bash
git clone https://github.com/Cosmic-Skye/makecmd.git
cd makecmd
./install.sh
```

## Usage

```bash
# Basic usage
makecmd "list all python files"
mkcmd "show disk usage"           # short alias

# Options
makecmd -d "delete temp files"    # dry run (print only)
makecmd -e "tar command"          # explain the command
makecmd -s "remove files"         # safe mode (read-only)
makecmd -n "list processes"       # no cache
```

## Configuration

Optional config file: `~/.makecmdrc`

```ini
output_mode = auto       # auto, prefill, clipboard, stdout
cache_ttl = 3600        # cache time in seconds
safe_mode = false       # restrict to read-only
```

## How it works

1. Takes your natural language input
2. Sends it to Claude via the CLI
3. Validates the returned command for safety
4. Shows you the command (never auto-executes)

Commands are cached to reduce API calls.

## License

GPL-3.0