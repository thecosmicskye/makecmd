#!/usr/bin/env zsh
#
# Zsh integration for makecmd
# This provides command prefilling functionality for zsh users

# Function to run makecmd and prefill the result
mkcmd() {
    local result
    local temp_file=$(mktemp)
    
    # Run the actual mkcmd command and capture output
    command mkcmd --output stdout "$@" > "$temp_file" 2>&1
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        # Extract the command from the output
        # Look for the line after "Generated command:"
        local cmd=$(grep -A1 "Generated command:" "$temp_file" | tail -n1)
        
        # If we found a command, prefill it
        if [[ -n "$cmd" ]]; then
            # Remove ANSI color codes
            cmd=$(echo "$cmd" | sed 's/\x1b\[[0-9;]*m//g')
            print -z "$cmd"
            echo "✓ Command pre-filled in terminal"
        else
            # Fallback: show the full output
            cat "$temp_file"
        fi
    else
        # Show error output
        cat "$temp_file"
    fi
    
    rm -f "$temp_file"
    return $exit_code
}

# Alias for consistency
alias makecmd=mkcmd