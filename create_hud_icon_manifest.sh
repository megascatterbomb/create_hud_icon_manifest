#!/bin/bash

MAPS_DIR="./maps"
POP_DIR="./scripts/population"
OUTPUT_FILE="./cfg/downloads.kv"

# Start writing to downloads.kv
echo '"Downloads"' > "$OUTPUT_FILE"
echo '{' >> "$OUTPUT_FILE"

# Iterate through each .bsp file in the maps directory
for map_file in "$MAPS_DIR"/*.bsp; do
    classicon_array=()  # Array to store ClassIcon names
    map_name=$(basename "$map_file" .bsp)
    map_base_files=()  # Array to store robot definition files referenced in the map's popfiles.
    map_templates=()  # Array to store template names found in this map
    
    # Iterate through the map's .pop files
    for pop_file in "$POP_DIR"/"$map_name"*.pop; do
        if [[ -f "$pop_file" ]]; then
			pop_name=$(basename $pop_file)
            # Extract direct ClassIcon references
            while read -r icon_name; do
                classicon_array+=("$icon_name")  # Store in array
				echo "$pop_name -> $icon_name"
            done < <(grep -ioP 'ClassIcon\s+\K\S+' "$pop_file")

            # Extract base template file references, ignoring anything after //
            base_files=($(grep -oP '^(?!.*//).*#base\s+\K\S+' "$pop_file"))
            map_base_files+=("${base_files[@]}")
            map_base_files=($(printf "%s\n" "${map_base_files[@]}" | sort -u))

            # Extract template names used in the main popfile, ignoring anything after //
            templates=($(grep -oP '^(?!.*//).*?\bTemplate\s+\K\S+' "$pop_file"))
            map_templates+=("${templates[@]}")
			map_templates=($(printf "%s\n" "${map_templates[@]}" | sort -u))
        fi
    done

    declare -A template_lookup
    for tmpl in "${map_templates[@]}"; do
        key="${tmpl//[[:space:]]/}"
        key="${key,,}"  # Lowercase (Bash 4+)
        template_lookup["$key"]="$tmpl"
    done

    # Process each base file
    for base_file in "${base_files[@]}"; do
        template_path="$POP_DIR/$base_file"
        if [[ -f "$template_path" ]]; then
            current_template=""
            
            while IFS= read -r raw_line || [[ -n $raw_line ]]; do
                # Remove comments
                line="${raw_line%%//*}"
                # Trim leading/trailing whitespace using Bash built-ins
                line="${line#"${line%%[![:space:]]*}"}"
                line="${line%"${line##*[![:space:]]}"}"

                [[ -z "$line" ]] && continue  # Skip empty lines

                # Normalize line for template match (lowercase + no whitespace)
                if [[ -z "$current_template" ]]; then
                    norm_line="${line//[[:space:]]/}"
                    norm_line="${norm_line,,}"
                    if [[ -n "${template_lookup[$norm_line]}" ]]; then
                        current_template="${template_lookup[$norm_line]}"
                        # echo "Processing line: $raw_line"  # Debugging output
                        # echo "Found template: $current_template"  # Debugging output
                        continue
                    fi
                fi

                # Look for ClassIcon line if a template was found
                if [[ -n "$current_template" ]]; then
                    # echo "Processing line: $line"  # Debugging output
                    if [[ "$line" =~ ^[[:space:]]*[Cc][Ll][Aa][Ss][Ss][Ii][Cc][Oo][Nn][[:space:]]+(.+)$ ]]; then
                        icon_name="${BASH_REMATCH[1]}"
                        # Trim trailing whitespace
                        icon_name="${icon_name%"${icon_name##*[![:space:]]}"}"
                        echo "$pop_name -> $base_file -> $current_template: $icon_name"
                        classicon_array+=("$icon_name")
                        current_template=""  # Reset for next template
                    fi
                fi
            done < "$template_path"
        fi
    done
    
    # Remove duplicates
    classicon_array=($(printf "%s\n" "${classicon_array[@]}" | sort -u))

    if [[ ${#classicon_array[@]} -gt 0 ]]; then
        echo -e "\t\"$map_name\"" >> "$OUTPUT_FILE"
        echo -e "\t{" >> "$OUTPUT_FILE"
        echo -e "\t\t\"Map\" \"$map_name\"" >> "$OUTPUT_FILE"
        
		for icon in "${classicon_array[@]}"; do
			vmt_path="materials/hud/leaderboard_class_${icon}.vmt"
		
			printf '\t\t"File" "%s"\n' "$vmt_path" >> "$OUTPUT_FILE"
		
			if [[ -f "$vmt_path" ]]; then
				base_texture=$(tr -d '\r' < "$vmt_path" | awk '
					BEGIN { IGNORECASE = 1 }
					/\$baseTexture/ && /hud\/leaderboard_class_/ {
						match($0, /"[^"]*"\s*"([^"]*hud\/leaderboard_class_[^"]*)"/, arr)
						if (arr[1] != "") {
							print arr[1]
							exit
						}
					}
				')
		
				if [[ -n "$base_texture" ]]; then
					texture_path="./materials/${base_texture}.vtf"
                    if [[ -f "$texture_path" ]]; then
                        echo "$icon -> $base_texture"
                        printf '\t\t"File" "materials/%s.vtf"\n' "$base_texture" >> "$OUTPUT_FILE"
                    else
                        echo "Warning: $icon references $base_texture.vtf but that file does not exist. Skipping." >&2
                    fi
				else
					echo "Warning: Could not extract baseTexture from $icon" >&2
				fi
			else
				echo "Warning: Missing .vmt file for $icon" >&2
			fi
		done
        echo -e "\t\t\"Precache\" \"Generic\"" >> "$OUTPUT_FILE"
        echo -e "\t}" >> "$OUTPUT_FILE"
    fi
done

# Close downloads.kv
echo '}' >> "$OUTPUT_FILE"

echo "downloads.kv file generated successfully in ./cfg/"
