#!/usr/bin/env bash
#
# Bash completion for makecmd
#
# Installation:
#   - Source this file in your .bashrc or .bash_profile
#   - Or copy to /etc/bash_completion.d/makecmd
#   - Or copy to /usr/local/etc/bash_completion.d/makecmd (for Homebrew)

_makecmd() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Options
    opts="-d --dry-run -e --explain -s --safe-mode -n --no-cache -D --debug -o --output -h --help -v --version --generate-config"
    
    # Output modes
    output_modes="auto prefill clipboard stdout"
    
    case "${prev}" in
        -o|--output)
            COMPREPLY=( $(compgen -W "${output_modes}" -- ${cur}) )
            return 0
            ;;
        *)
            ;;
    esac
    
    # Complete options
    if [[ ${cur} == -* ]] ; then
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi
}

# Register completion for both makecmd and mkcmd
complete -F _makecmd makecmd
complete -F _makecmd mkcmd