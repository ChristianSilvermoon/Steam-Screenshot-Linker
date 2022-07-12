#!/bin/bash

# XDG Directories
: ${XDG_CONFIG_HOME:=$HOME/.config}
CONF_DIR=$XDG_CONFIG_HOME/steam-screenshot-linker
if [ ! -d "$CONF_DIR" ]; then
	mkdir -p "$CONF_DIR"
fi

# Important Directories
STEAM_DIR=$HOME/.steam/steam
TARGET_DIR=$HOME/Pictures/Screenshots/Steam

# Attempt to read STEAM_UID from config file
if [ -f "$CONF_DIR/STEAM_UID" ]; then
	STEAM_UID="$(cat "$CONF_DIR/STEAM_UID")"

	if [ ! -d "$STEAM_DIR/userdata/$STEAM_UID" ]; then
		echo "No userdata For: $STEAM_UID"
		exit 1
	else
		echo "Loaded Steam UID from config: $STEAM_UID"
	fi

elif [ -t 1 ]; then 
	# If we can't, prompt user to select one:


	# Determine available Steam Accounts
	accounts=()
	for x in $STEAM_DIR/userdata/*; do
		x="$(basename "$x")"
		if [ "$x" != "ac" ]; then
			dname=$(cat $STEAM_DIR/userdata/$x/config/localconfig.vdf | grep "PersonaName" | tr -d '\t' | sed 's/^"PersonaName""//g; s/"$//g')
			accounts+=( "$x ($dname)" );
		fi
	done 

	# Prompt User to select one
	until [ "$STEAM_UID" ]; do
	
		echo "Select a Steam User ID to use, or Q to quit"
		select STEAM_UID in "${accounts[@]}"; do
			echo "Selected: $STEAM_UID"
			[ "${STEAM_UID,,}" = "q" ] && exit
			STEAM_UID="${STEAM_UID/ *}"
			break
		done

		# Save ID
		echo "$STEAM_UID" > "$CONF_DIR/STEAM_UID"
	done

else
	echo "Unable to continue, non-interactive terminal or Pipe"
	exit 1
fi

SCR_DIR="$STEAM_DIR/userdata/$STEAM_UID/760/remote"

# Make sure important directories exist
if [ ! -d "$STEAM_DIR" ]; then
	echo "Steam Directory Does not Exist:"
	echo "  $STEAM_DIR"
	exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
	mkdir -p "$TARGET_DIR"
fi

if [ ! -d "$SCR_DIR" ]; then
	echo "Screenshot directory does not exist"
	echo "   $SCR_DIR"
	exit 1
fi


# Locate Steam Library Directories
mapfile -t LDIRS < <(cat "$STEAM_DIR/config/libraryfolders.vdf" | grep "path" | tr -d '\t' | sed 's/^"path""//g; s/"$//g')

echo "Steam Libraries are:"
for x in "${LDIRS[@]}"; do
	echo "  * $x"
done

echo ""

# Figure out which directores belong to which games...
echo "Screenshot Directory Contents:"
declare -A games
for x in $SCR_DIR/*; do
	x=$(basename "$x")
	for d in ${LDIRS[@]}; do

		if [ -f "$d/steamapps/appmanifest_${x}.acf" ]; then
			M="$d/steamapps/appmanifest_${x}.acf"

			# Read Name from located App Manifest
			name=$(cat "$M" | grep "name" | tr -d '\t' | sed 's/^"name""//g; s/"$//g')

			# Filter Name For invalid or Undesriable characters
			name="$(echo "$name" | sed -E 's/:/ -/g; s/(\$|\/|!)/_/g')"

			# If no name; don't add to array
			[ "$name" ] || continue

			# Store Name for ID in games array
			if [ "$name" ]; then
				games[$x]="$name"
			fi
		fi
	done
done

# Create Symlinks @ $TARGET_DIR
for x in ${!games[@]}; do
	echo "  * ${games[$x]} ($x)"

	GSD="$SCR_DIR/$x/screenshots"
	echo "     $(ls -1 "$GSD" | wc -l) Screenshots"

	if [ ! -e "$TARGET_DIR/${games[$x]}" ]; then
		ln -sf "$GSD" "$TARGET_DIR/${games[$x]}"
	fi
done

if [ ! -e "$TARGET_DIR/All" ]; then
	ln -sf "$SCR_DIR" "$TARGET_DIR/All"
fi
