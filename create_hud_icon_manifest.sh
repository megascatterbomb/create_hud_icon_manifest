#!/bin/bash

verbose=false

# Parse options
while getopts "v" opt; do
    case $opt in
        v) verbose=true ;;
    esac
done

vlog() {
    if $verbose; then
        echo "$1"
    fi
}

MAPS_DIR="./maps"
POP_DIR="./scripts/population"
OUTPUT_FILE="./cfg/downloads.kv"

# Ignore vanilla icons
IGNORE_ICONS=(
    "critical"
    "demo"
    "demoknight"
    "demoknight_giant"
    "demoknight_samurai"
    "demo_bomber"
    "demo_burst"
    "demo_burst_crit"
    "demo_burst_giant"
    "demo_d"
    "demo_giant"
    "engineer"
    "engineer_d"
    "heavy"
    "heavy_champ"
    "heavy_champ_giant"
    "heavy_chief"
    "heavy_crit"
    "heavy_d"
    "heavy_deflector"
    "heavy_deflector_healonkill"
    "heavy_deflector_healonkill_crit"
    "heavy_deflector_push"
    "heavy_giant"
    "heavy_gru"
    "heavy_gru_giant"
    "heavy_heater"
    "heavy_heater_giant"
    "heavy_mittens"
    "heavy_shotgun"
    "heavy_shotgun_giant"
    "heavy_steelfist"
    "heavy_urgent"
    "medic"
    "medic_d"
    "medic_giant"
    "medic_uber"
    "pyro"
    "pyro_d"
    "pyro_flare"
    "pyro_flare_giant"
    "pyro_giant"
    "scout"
    "scout_bat"
    "scout_bonk"
    "scout_bonk_giant"
    "scout_d"
    "scout_fan"
    "scout_fan_giant"
    "scout_giant"
    "scout_giant_fast"
    "scout_jumping"
    "scout_jumping_g"
    "scout_shortstop"
    "scout_stun"
    "scout_stun_armored"
    "scout_stun_giant"
    "scout_stun_giant_armored"
    "sentry_buster"
    "sniper"
    "sniper_bow"
    "sniper_bow_multi"
    "sniper_d"
    "sniper_jarate"
    "sniper_sydneysleeper"
    "soldier"
    "soldier_backup"
    "soldier_backup_giant"
    "soldier_barrage"
    "soldier_blackbox"
    "soldier_blackbox_giant"
    "soldier_buff"
    "soldier_buff_giant"
    "soldier_burstfire"
    "soldier_conch"
    "soldier_conch_giant"
    "soldier_crit"
    "soldier_d"
    "soldier_giant"
    "soldier_libertylauncher"
    "soldier_libertylauncher_giant"
    "soldier_major_crits"
    "soldier_sergeant_crits"
    "soldier_spammer"
    "soldier_spammer_crit"
    "special_blimp"
    "spy"
    "spy_d"
    "tank"
    "teleporter"
)

# Start writing to downloads.kv
echo '"Downloads"' > "$OUTPUT_FILE"
echo '{' >> "$OUTPUT_FILE"

# Iterate through each .bsp file in the maps directory
for map_file in "$MAPS_DIR"/*.bsp; do
    classicon_array=()  # Array to store ClassIcon names
    map_name=$(basename "$map_file" .bsp)
    map_base_files=()  # Array to store robot definition files referenced in the map's popfiles.
    map_templates=()  # Array to store template names found in this map

    echo "Processing map: $map_name"
    
    # Iterate through the map's .pop files
    for pop_file in "$POP_DIR"/"$map_name"*.pop; do
        if [[ -f "$pop_file" ]]; then
			pop_name=$(basename $pop_file)
            # Extract direct ClassIcon references
            while read -r icon_name; do
                classicon_array+=("$icon_name")  # Store in array
				vlog "$pop_name -> $icon_name"
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

    unset 'template_lookup'
    declare -A template_lookup
    for tmpl in "${map_templates[@]}"; do
        key="${tmpl//[[:space:]]/}"
        key="${key,,}"  # Lowercase (Bash 4+)
        template_lookup["$key"]="$tmpl"
    done

    # Process each base file
    for base_file in "${map_base_files[@]}"; do
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
                        vlog "$pop_name -> $base_file -> $current_template: $icon_name"
                        classicon_array+=("$icon_name")
                        current_template=""  # Reset for next template
                    fi
                fi
            done < "$template_path"
        fi
    done

    # Remove vanilla icons
    tmp=()
    for item in "${classicon_array[@]}"; do
        skip=false
        for ex in "${IGNORE_ICONS[@]}"; do
            if [[ "$item" == "$ex" ]]; then
                skip=true
                break
            fi
        done
        if ! $skip; then
            tmp+=("$item")
        fi
    done

    classicon_array=("${tmp[@]}")
    
    # Remove duplicates
    classicon_array=($(printf "%s\n" "${classicon_array[@]}" | sort -u))
    vtf_files=()

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
                        vtf_files+=("$base_texture")
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
        vlog "VTF Files:"
        # Remove duplicates
        vtf_files=($(printf "%s\n" "${vtf_files[@]}" | sort -u))
        for vtf_file in "${vtf_files[@]}"; do
            vlog "$vtf_file.vtf"
            printf '\t\t"File" "materials/%s.vtf"\n' "$vtf_file" >> "$OUTPUT_FILE"
        done

        echo -e "\t\t\"Precache\" \"Generic\"" >> "$OUTPUT_FILE"
        echo -e "\t}" >> "$OUTPUT_FILE"
    fi
done

# Close downloads.kv
echo '}' >> "$OUTPUT_FILE"

echo "downloads.kv file generated successfully in ./cfg/"
