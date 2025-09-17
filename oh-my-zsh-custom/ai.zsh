alias inspect-mcp="npx @modelcontextprotocol/inspector kitsune-mcp"

# Configurable aichat command variables
AI_CHAT_COMMAND=$(which aichat 2>/dev/null)
AI_EXECUTE=("$AI_CHAT_COMMAND" "-e")
AI_CHAT="$AI_CHAT_COMMAND"

# Use aichat to handle unknown commands
command_not_found_handler() {
   $AI_EXECUTE "$@"
}

# Explain a command using aichat
explain() {
    $AI_CHAT "$@"
}

# Same as explain, but allows 'explain:' syntax
explain:() {
    $AI_CHAT "$@"
}

# ZLE widget: send current buffer to aichat and replace with result
_aichat_zsh() {

    if [[ -n "$BUFFER" ]]; then
        local _old=$BUFFER
        BUFFER+="⌛"
        zle -I && zle redisplay
        if [[ "$(uname)" == "Darwin" ]]; then
            BUFFER=$(echo $AI_EXECUTE "$_old")
        else
            BUFFER=$($AI_EXECUTE "$_old")
        fi
        zle end-of-line
    fi
}
zle -N _aichat_zsh

# Generate a commit message using aichat and git diff
ai_commit_msg() {
    $AI_CHAT "generate a commit message for the following $(git diff)"
}

# ZLE widget for ai_commit_msg (menu-based file selection with "All" option)
_ai_commit_msg_zsh() {
    # Use local -a for arrays
    local -a files_array # Declare files_array as an array
    local files_string tmpfile msg changes added_files # files_string will hold the space-separated list initially
    local repo_root

    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -z "$repo_root" ]]; then
        BUFFER="" # Clear any pending message
        zle -I && zle redisplay
        zle -M "Error: Not a git repository."
        return 1
    fi

    # buffer equals an hourglass
    BUFFER="⌛ Generating commit message..."
    zle -I && zle redisplay

    # Get lists of files by status
    local staged_files modified_files untracked_files deleted_files
    staged_files=$(git -C "$repo_root" diff --name-only --cached)
    modified_files=$(git -C "$repo_root" ls-files -m --exclude-standard)
    untracked_files=$(git -C "$repo_root" ls-files -o --exclude-standard)
    deleted_files=$(git -C "$repo_root" ls-files -d --exclude-standard) # Deleted from worktree, not staged for deletion

    local fzf_display_list=""
    # Append prefixed files to fzf_display_list, ensuring a newline after each block if not empty
    [[ -n "$staged_files" ]]    && fzf_display_list+=$(echo "$staged_files"    | sed 's/^/S: /')$'\n'
    [[ -n "$modified_files" ]]  && fzf_display_list+=$(echo "$modified_files"  | sed 's/^/M: /')$'\n'
    [[ -n "$untracked_files" ]] && fzf_display_list+=$(echo "$untracked_files" | sed 's/^/U: /')$'\n'
    [[ -n "$deleted_files" ]]   && fzf_display_list+=$(echo "$deleted_files"   | sed 's/^/D: /')$'\n'

    # Sort unique entries, remove blank lines.
    fzf_display_list=$(echo -e "${fzf_display_list}" | grep . | sort -u)

    # This list contains all unique file paths for the "All files" option
    local all_candidate_files_combined
    all_candidate_files_combined=$(printf "%s\n%s\n%s\n%s" "$staged_files" "$modified_files" "$untracked_files" "$deleted_files" | grep . | sort -u)

    if [[ -z "$fzf_display_list" ]]; then
        zle -M "No files found to commit (staged, modified, untracked, or deleted)."
        BUFFER=""
        zle -I && zle redisplay
        return 1
    fi

    # Use fzf or prompt for file selection
    if command -v fzf >/dev/null 2>&1; then
        local fzf_input_string
        fzf_input_string="All files (select this to include all listed files)\n$fzf_display_list"

        files_string=$(echo -e "$fzf_input_string" | fzf -m --prompt="Select files for commit (S:Staged M:Modified U:Untracked D:Deleted): " --header="TAB to select, ENTER to confirm")

        if [[ -z "$files_string" ]]; then
           BUFFER="" # Clear hourglass
           zle -I && zle redisplay
           zle -M "No files selected."
           return 1
        fi

        local selected_lines_array=("${(@f)files_string}") # Split selection into an array of lines
        local use_all_files=0
        for selected_item in "${selected_lines_array[@]}"; do
            if [[ "$selected_item" == "All files (select this to include all listed files)" ]]; then
                use_all_files=1
                break
            fi
        done

        if [[ $use_all_files -eq 1 ]]; then
            if [[ -z "$all_candidate_files_combined" ]]; then # Should be caught by earlier empty check
                BUFFER=""
                zle -I && zle redisplay
                zle -M "No files to commit for 'All files' selection."
                return 1
            fi
            files_array=("${(@f)all_candidate_files_combined}")
        else
            # User selected specific files. Strip prefixes.
            files_array=() # Reset
            for line in "${selected_lines_array[@]}"; do
                # Prefix is 3 characters (e.g., "S: ", "M: ")
                files_array+=("${line:3}")
            done
        fi
    else
        # Fallback: Simple prompt (less user-friendly for many files)
        # This fallback needs to be adapted if we want to keep it, as it doesn't understand prefixes.
        # For now, focusing on the fzf path. The original fallback logic might need rethinking
        # or removal if fzf is a hard dependency for this enhanced feature.
        # For simplicity, let's assume fzf is available for this complex selection.
        # If you need the fallback, it should probably just use `all_candidate_files_combined` for 'all'
        # and expect raw paths for specific files.
        zle -M "fzf is required for advanced file selection. Please install fzf or simplify selection."
        BUFFER=""
        zle -I && zle redisplay
        return 1
    fi

    # Check if the array is actually empty after processing selections
    if [[ ${#files_array[@]} -eq 0 ]]; then
        BUFFER="" # Clear hourglass
        zle -I && zle redisplay
        zle -M "No files selected or determined from input."
        return 1
    fi

    tmpfile=$(mktemp /tmp/ai-commit-msg.XXXXXX)
    # Add only the selected files to staging.
    # `git add` will correctly handle staging for new, modified, or deleted files,
    # and do nothing for already staged files.
    git -C "$repo_root" add -- "${files_array[@]}"


    # Debugging: Use the array correctly
    # Use print -r -- to safely print array elements, one per line typically
    # print -r -- "Selected files array:" "${files_array[@]}"


    # Default 'git diff' is unstaged changes in working dir vs index.
    # Use the array expansion "${files_array[@]}"

    # Run git diff from the repository root
    changes=$(git -C "$repo_root" diff --cached -- "${files_array[@]}")
    added_files=$(git -C "$repo_root" diff --cached --name-only --diff-filter=A -- "${files_array[@]}") # Ensure diff is also scoped

    # Check if changes are empty *before* calling AI
    if [[ -z "$changes" && -z "$added_files" ]]; then
        # Option 2: Proceed (AI might still generate a generic message)
        print -r -- "Warning: No changes or added files detected via 'git diff' for selected files."
    fi

    # Ensure $AI_CHAT is defined and executable
    if ! command -v "$AI_CHAT" >/dev/null 2>&1; then
       set +x
       BUFFER="" # Clear hourglass
       zle -I && zle redisplay
       zle -M "Error: AI command '$AI_CHAT' not found or not executable."
       rm -f $tmpfile # Clean up
       trap - INT TERM EXIT # Remove trap
       return 1
    fi

    # Call the AI, quoting the changes variable
    msg="$($AI_CHAT "generate a short, concise and accurate commit message (using conventional commits format, plain text only, no markdown ticks) for the following changes: $changes, added files: $added_files")"
    # Check if AI returned an empty message
    if [[ -z "$msg" ]]; then
        BUFFER="" # Clear hourglass
        zle -I && zle redisplay
        zle -M "Warning: AI returned an empty commit message."
        # Decide: continue with empty message or abort? Let's continue for now.
    fi


    # Write message to temp file
    echo "$msg" > "$tmpfile"

    # Add the selected files using the array
    # This correctly handles filenames with spaces or special characters

    # Set the buffer for the commit command
    BUFFER="git commit -F $tmpfile"
    zle end-of-line # Move cursor to the end

}

# Make the function available as a widget
zle -N _ai_commit_msg_zsh

# Optional: Bind it to a key sequence (e.g., Alt+C)
# bindkey '^[c' _ai_commit_msg_zsh


# Keybindings for _aichat_zsh:
#   Alt-e in emacs mode, vi insert mode, and vi command mode
bindkey '\ee' _aichat_zsh
bindkey -M viins '\ee' _aichat_zsh
bindkey -M vicmd '\ee' _aichat_zsh

# Keybinding for ai_commit_msg:
#   Alt-g in emacs mode, vi insert mode, and vi command mode
bindkey '\eg' _ai_commit_msg_zsh
bindkey -M viins '\eg' _ai_commit_msg_zsh
bindkey -M vicmd '\eg' _ai_commit_msg_zsh
