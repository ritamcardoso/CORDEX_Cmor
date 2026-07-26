#!/bin/bash

output_file="summary_list.txt"
> "$output_file"

# Enable flexible matching options
shopt -s nullglob nocaseglob

# Find all files containing 'run_out' anywhere in the name
files=( *run_out* )

# Filter down to regular files only (excluding directories)
valid_files=()
for f in "${files[@]}"; do
    [ -f "$f" ] && valid_files+=("$f")
done

if [ ${#valid_files[@]} -eq 0 ]; then
    echo "Error: No files matching '*run_out*' found in $(pwd)"
    exit 1
fi

echo "Found ${#valid_files[@]} matching file(s)."

for file in "${valid_files[@]}"; do
    echo "Processing $file..."
    
    # Extract matching lines (handles minor spacing variations & case-insensitivity)
    match=$(grep -i -E -m 1 "declare[[:space:]]+-a[[:space:]]+var=" "$file")
    
    echo "File: $file" >> "$output_file"
    
    if [ -n "$match" ]; then
        echo "$match" >> "$output_file"
    else
        echo "[No 'declare -a var=' line found inside]" >> "$output_file"
    fi
    
    echo "----------------------------------------" >> "$output_file"
done

echo "Done! Results saved to $output_file"
