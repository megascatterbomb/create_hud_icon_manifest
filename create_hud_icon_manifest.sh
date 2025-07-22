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
    
    # Iterate through relevant .pop files
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

            # Extract, sort, and deduplicate template names used in the main popfile, ignoring anything after //
            templates=($(grep -oP '^(?!.*//).*?\bTemplate\s+\K\S+' "$pop_file"))
			templates=($(printf "%s\n" "${templates[@]}" | sort -u))

            # Iterate through base template files
            for base_file in "${base_files[@]}"; do
                template_path="$POP_DIR/$base_file"
                if [[ -f "$template_path" ]]; then
                    # Find only referenced template definitions and extract ClassIcons
                    for template in "${templates[@]}"; do
                        class_icon=$(awk -v tmpl="$template" '
                            {
								clean_line = $0;
								gsub("//.*", "", clean_line)  # Remove anything after "//"
								gsub(/[[:space:]]/, "", clean_line);  # Remove ALL whitespace characters from line
								clean_line = tolower(clean_line)
								clean_tmpl = tmpl;
								gsub("//.*", "", clean_tmpl)  # Remove anything after "//"
								clean_tmpl = tolower(clean_tmpl)

								if (clean_line == clean_tmpl) {
									found=1;
								}
							}
                            found && tolower($0) ~ /classicon/ {
                                gsub("//.*", "", $2)  # Remove anything after "//"
                                print $2
								found=0
                                exit
                            }
                        ' "$template_path")

                        if [[ -n "$class_icon" ]]; then
							
							echo "$pop_name -> $base_file -> $template: $class_icon"
							classicon_array+=("$(echo "$class_icon" | tr -d '\r\n')")
                        fi
                    done
                fi
            done
        fi
    done
    
    # Remove duplicates
    classicon_array=($(printf "%s\n" "${classicon_array[@]}" | sort -u))

    if [[ ${#classicon_array[@]} -gt 0 ]]; then
        echo -e "\t\"$map_name\"" >> "$OUTPUT_FILE"
        echo -e "\t{" >> "$OUTPUT_FILE"
        echo -e "\t\t\"Map\" \"$map_name\"" >> "$OUTPUT_FILE"
	# 
    #     for icon in "${classicon_array[@]}"; do
    #         printf '\t\t"File" "materials/hud/leaderboard_class_%s.vmt"\n' "$icon" >> "$OUTPUT_FILE"
    #         printf '\t\t"File" "materials/hud/leaderboard_class_%s.vtf"\n' "$icon" >> "$OUTPUT_FILE"
	# 		
	# 		# If the icon ends with "_giant", also include the non-giant .vtf file
    #         if [[ "$icon" == *_giant ]]; then
    #             non_giant_icon="${icon%_giant}"  # Remove "_giant" suffix
    #             printf '\t\t"File" "materials/hud/leaderboard_class_%s.vtf"\n' "$non_giant_icon" >> "$OUTPUT_FILE"
    #         fi
    #     done
	# 
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
					printf '\t\t"File" "materials/%s.vtf"\n' "$base_texture" >> "$OUTPUT_FILE"
				else
					echo "Warning: Could not extract baseTexture from $vmt_path" >&2
				fi
			else
				echo "Warning: Missing VMT file $vmt_path" >&2
			fi
		done
        echo -e "\t\t\"Precache\" \"Generic\"" >> "$OUTPUT_FILE"
        echo -e "\t}" >> "$OUTPUT_FILE"
    fi
done

# Close downloads.kv
echo '}' >> "$OUTPUT_FILE"

echo "downloads.kv file generated successfully in ./cfg/"
