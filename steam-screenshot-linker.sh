#!/bin/bash
declare -r VERSION="22.7.15b"
shopt -s checkwinsize && (: )

# XDG Directories
: ${XDG_CONFIG_HOME:=$HOME/.config}
CONF_DIR=$XDG_CONFIG_HOME/steam-screenshot-linker
if [ ! -d "$CONF_DIR" ]; then
	mkdir -p "$CONF_DIR"
fi


# Important Directories
STEAM_DIR=$HOME/.steam/steam
TARGET_DIR=$HOME/Pictures/Screenshots/Steam

help_line() {
	printf "   %-30s %s\n" "$1" "$2"
}

help_msg() {
	echo -e  "\e[1m${0##*\/}\e[22m - Links Steam Screenshot Folders"

	
	echo -e "\n\e[1mVERSION\e[22m\n   $VERSION"

	echo -e "\n\e[1mOPTIONS\e[22m"

	help_line "--delete-config, -d" "Delete config (\$XDG_CONFIG_HOME/steam-screenshot-linker)"
	help_line "--id=STEAM_UID, -i STEAM_UID" "Use Steam User ID, ignoring config"
	help_line "--source=DIR, -s" "Path to Steam Installation"
	help_line "--target=DIR, -t <DIR>" "Directory to create symlinks in"
	help_line "--help, -?" "Display this message"

	echo -e "\n\e[1mCONFIG\e[22m"
	if [ -f "$XDG_CONFIG_HOME/steam-screenshot-linker/STEAM_UID" ]; then
		echo -e "  \e[3;32m${XDG_CONFIG_HOME/$HOME/\~}/steam-screenshot-linker/STEAM_UID\e[22;23;37m"
		echo -e "    \e[2;3m$(cat "$XDG_CONFIG_HOME/steam-screenshot-linker/STEAM_UID")\e[22;23;37m"
	else
		echo -e "  \e[3;31mNo file @ ${XDG_CONFIG_HOME/$HOME/\~}/steam-screenshot-linker/STEAM_UID\e[23;37m"
	fi
}

err() {
	echo "$@" >&2
}

verify_steam_directory() {
	if
		[ -d "$STEAM_DIR" ] &&
		[ -d "$STEAM_DIR/userdata" ] &&
		[ -d "$STEAM_DIR/steamapps" ]
	then
		return 0
	else
		return 1
	fi
}

arg_handler() {
	local ARG exp exc

	for ARG; do
		# Expecting followup argument
		case $exp in
			"id")
				STEAM_UID="$ARG"
				exc=""
				exp=""
				continue
				;;
			"source")
				STEAM_DIR="$ARG"
				exc=""
				exp=""
				continue
				;;
			"target")
				TARGET_DIR="$ARG"
				exc=""
				exp=""
				continue
			;;
		esac

		# Primary Argument handling
		case $ARG in
			"--help"|"-?")
				help_msg
				exit
				;;
			"--target="*)
					TARGET_DIR="${ARG/--target=}"
				;;
			"-t")
					exc="-t"
					exp=target
				;;
			"--source="*)
					STEAM_DIR="${ARG/--source=}"
				;;
			"-s")
					exc="-s"
					exp=source
				;;
			"--id="*)
				STEAM_UID="${ARG/--id=}"
				;;
			"-i")
					exc="-i"
					exp=id
				;;
			"--delete"|"-d")
					echo -e "\e[1mThis will \e[31mDELETE\e[37m the following:\e[22m\n  $XDG_CONFIG_HOME/steam-screenshot-linker\n"
					echo -en "\e[1mAre you \e[4mSURE\e[24m? [Y/N*]\e[22m "
					read -rsn1 yorn
					echo ""
					if [ "${yorn,,}" = "y" ]; then
						rm -rf "$XDG_CONFIG_HOME/steam-screenshot-linker" &>/dev/null

					fi
					exit
				;;
			*)
				err -e "\e[31;1mInvalid Argument: $ARG\e[22;37m"
				exit 1
			;;
		esac
	done
}

save_config() {
		# Save ID
		echo "$STEAM_UID" > "$CONF_DIR/STEAM_UID"
}

read_config() {
	# Attempt to read STEAM_UID from config file
	if [ -f "$CONF_DIR/STEAM_UID" ]; then
		STEAM_UID="$(cat "$CONF_DIR/STEAM_UID")"

		if [ ! -d "$STEAM_DIR/userdata/$STEAM_UID" ]; then
			echo "No userdata For: $STEAM_UID"
			return 1
		else
			echo "Loaded Steam UID from config: $STEAM_UID"
		fi
	else
		return 1
	fi
}

prompt_id() {
	local PS3="$(echo -e "\e[1mSelection: \e[22m")"
	# Prompt User to select an account
	local accounts dname x
 
	# Determine available Steam Accounts
	accounts=()
	for x in $STEAM_DIR/userdata/*; do
		x="$(basename "$x")"
		if [ "$x" != "ac" ]; then
			dname=$(cat $STEAM_DIR/userdata/$x/config/localconfig.vdf | grep "PersonaName" | tr -d '\t' | sed 's/^"PersonaName""//g; s/"$//g')
			accounts+=( "$x ($dname)" );
		fi
	done 

	# If Only one, select one
	if [ "${#accounts[@]}" = "1" ]; then
		echo "Automatically using User Data From: ${accounts[0]}"
		STEAM_UID=${accounts[0]/ *}
		return
	fi

	# Prompt User to select one
	until [ "$STEAM_UID" ]; do
	
		echo -e "\e[1mSelect a Steam Userdata Directory to use, or Q to quit:\e[22m"
		select STEAM_UID in "${accounts[@]}"; do
			echo -e "  \e[2;3mSelected \"$STEAM_UID\"\e[22;23m"
			[ "${STEAM_UID,,}" = "q" ] && exit
			STEAM_UID="${STEAM_UID/ *}"
			break
		done
	done
}

# Locate Steam Library Directories
locate_libraries() {
	mapfile -t LDIRS < <(cat "$STEAM_DIR/config/libraryfolders.vdf" | grep "path" | tr -d '\t' | sed 's/^"path""//g; s/"$//g')

	echo -e "\e[1mSteam Libraries are:\e[22m"
	for x in "${LDIRS[@]}"; do
		echo "  * $x"
	done
}

# Figure out which directores belong to which games...
idgames() {
	declare -gA games
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
}

mklinks() {
	# Create Symlinks @ $TARGET_DIR
	echo -e "\e[1mScreenshot Directory Contents:\e[22m"
	for x in ${!games[@]}; do

		echo -en "  * \e[$((x % 6 + 31))m"
		echo "${games[$x]} ($x)"
		echo -en "\e[37;22m"

		GSD="$SCR_DIR/$x/screenshots"
		echo -en "\e[2;3m"
		echo -e "     $(ls -1 "$GSD" | wc -l) Screenshots\e[22;23m"

		if [ ! -e "$TARGET_DIR/${games[$x]}" ]; then
			ln -sf "$GSD" "$TARGET_DIR/${games[$x]}"
		fi
	done

	if [ ! -e "$TARGET_DIR/All" ]; then
		ln -sf "$SCR_DIR" "$TARGET_DIR/All"
	fi
}

splash() {
# Generated with:  echo "Steam Screenshot Linker" | figlet -w $COLUMNS -f smblock | lolcat -f
# Stored here like this to avoid depending on figlet & lolcat
echo "
[38;5;164m▞[0m[38;5;164m▀[0m[38;5;164m▖[0m[38;5;128m▐[0m[38;5;128m [0m[38;5;129m [0m[38;5;129m [0m[38;5;129m [0m[38;5;129m [0m[38;5;129m [0m[38;5;129m [0m[38;5;129m [0m[38;5;129m [0m[38;5;129m [0m[38;5;93m [0m[38;5;93m [0m[38;5;93m [0m[38;5;93m▞[0m[38;5;93m▀[0m[38;5;93m▖[0m[38;5;93m [0m[38;5;93m [0m[38;5;93m [0m[38;5;99m [0m[38;5;63m [0m[38;5;63m [0m[38;5;63m [0m[38;5;63m [0m[38;5;63m [0m[38;5;63m [0m[38;5;63m [0m[38;5;63m [0m[38;5;63m [0m[38;5;63m [0m[38;5;63m [0m[38;5;69m [0m[38;5;33m [0m[38;5;33m [0m[38;5;33m▌[0m[38;5;33m [0m[38;5;33m [0m[38;5;33m [0m[38;5;33m [0m[38;5;33m [0m[38;5;33m▐[0m[38;5;39m [0m[38;5;39m [0m[38;5;39m [0m[38;5;39m▌[0m[38;5;39m [0m[38;5;39m [0m[38;5;39m▗[0m[38;5;39m [0m[38;5;39m [0m[38;5;38m [0m[38;5;38m [0m[38;5;44m▌[0m[38;5;44m [0m[38;5;44m [0m[38;5;44m [0m[38;5;44m [0m[38;5;44m [0m[38;5;44m [0m[38;5;44m [0m[38;5;44m [0m
[38;5;128m▚[0m[38;5;128m▄[0m[38;5;129m [0m[38;5;129m▜[0m[38;5;129m▀[0m[38;5;129m [0m[38;5;129m▞[0m[38;5;129m▀[0m[38;5;129m▖[0m[38;5;129m▝[0m[38;5;129m▀[0m[38;5;93m▖[0m[38;5;93m▛[0m[38;5;93m▚[0m[38;5;93m▀[0m[38;5;93m▖[0m[38;5;93m [0m[38;5;93m▚[0m[38;5;93m▄[0m[38;5;93m [0m[38;5;99m▞[0m[38;5;63m▀[0m[38;5;63m▖[0m[38;5;63m▙[0m[38;5;63m▀[0m[38;5;63m▖[0m[38;5;63m▞[0m[38;5;63m▀[0m[38;5;63m▖[0m[38;5;63m▞[0m[38;5;63m▀[0m[38;5;63m▖[0m[38;5;69m▛[0m[38;5;33m▀[0m[38;5;33m▖[0m[38;5;33m▞[0m[38;5;33m▀[0m[38;5;33m▘[0m[38;5;33m▛[0m[38;5;33m▀[0m[38;5;33m▖[0m[38;5;33m▞[0m[38;5;39m▀[0m[38;5;39m▖[0m[38;5;39m▜[0m[38;5;39m▀[0m[38;5;39m [0m[38;5;39m [0m[38;5;39m▌[0m[38;5;39m [0m[38;5;39m [0m[38;5;38m▄[0m[38;5;38m [0m[38;5;44m▛[0m[38;5;44m▀[0m[38;5;44m▖[0m[38;5;44m▌[0m[38;5;44m▗[0m[38;5;44m▘[0m[38;5;44m▞[0m[38;5;44m▀[0m[38;5;44m▖[0m[38;5;44m▙[0m[38;5;43m▀[0m[38;5;49m▖[0m
[38;5;129m▖[0m[38;5;129m [0m[38;5;129m▌[0m[38;5;129m▐[0m[38;5;129m [0m[38;5;129m▖[0m[38;5;129m▛[0m[38;5;129m▀[0m[38;5;93m [0m[38;5;93m▞[0m[38;5;93m▀[0m[38;5;93m▌[0m[38;5;93m▌[0m[38;5;93m▐[0m[38;5;93m [0m[38;5;93m▌[0m[38;5;93m [0m[38;5;99m▖[0m[38;5;63m [0m[38;5;63m▌[0m[38;5;63m▌[0m[38;5;63m [0m[38;5;63m▖[0m[38;5;63m▌[0m[38;5;63m [0m[38;5;63m [0m[38;5;63m▛[0m[38;5;63m▀[0m[38;5;63m [0m[38;5;69m▛[0m[38;5;33m▀[0m[38;5;33m [0m[38;5;33m▌[0m[38;5;33m [0m[38;5;33m▌[0m[38;5;33m▝[0m[38;5;33m▀[0m[38;5;33m▖[0m[38;5;33m▌[0m[38;5;39m [0m[38;5;39m▌[0m[38;5;39m▌[0m[38;5;39m [0m[38;5;39m▌[0m[38;5;39m▐[0m[38;5;39m [0m[38;5;39m▖[0m[38;5;39m [0m[38;5;38m▌[0m[38;5;38m [0m[38;5;44m [0m[38;5;44m▐[0m[38;5;44m [0m[38;5;44m▌[0m[38;5;44m [0m[38;5;44m▌[0m[38;5;44m▛[0m[38;5;44m▚[0m[38;5;44m [0m[38;5;44m▛[0m[38;5;43m▀[0m[38;5;49m [0m[38;5;49m▌[0m[38;5;49m [0m[38;5;49m [0m
[38;5;129m▝[0m[38;5;129m▀[0m[38;5;129m [0m[38;5;129m [0m[38;5;129m▀[0m[38;5;93m [0m[38;5;93m▝[0m[38;5;93m▀[0m[38;5;93m▘[0m[38;5;93m▝[0m[38;5;93m▀[0m[38;5;93m▘[0m[38;5;93m▘[0m[38;5;93m▝[0m[38;5;99m [0m[38;5;63m▘[0m[38;5;63m [0m[38;5;63m▝[0m[38;5;63m▀[0m[38;5;63m [0m[38;5;63m▝[0m[38;5;63m▀[0m[38;5;63m [0m[38;5;63m▘[0m[38;5;63m [0m[38;5;63m [0m[38;5;69m▝[0m[38;5;33m▀[0m[38;5;33m▘[0m[38;5;33m▝[0m[38;5;33m▀[0m[38;5;33m▘[0m[38;5;33m▘[0m[38;5;33m [0m[38;5;33m▘[0m[38;5;33m▀[0m[38;5;39m▀[0m[38;5;39m [0m[38;5;39m▘[0m[38;5;39m [0m[38;5;39m▘[0m[38;5;39m▝[0m[38;5;39m▀[0m[38;5;39m [0m[38;5;39m [0m[38;5;38m▀[0m[38;5;38m [0m[38;5;44m [0m[38;5;44m▀[0m[38;5;44m▀[0m[38;5;44m▘[0m[38;5;44m▀[0m[38;5;44m▘[0m[38;5;44m▘[0m[38;5;44m [0m[38;5;44m▘[0m[38;5;44m▘[0m[38;5;43m [0m[38;5;49m▘[0m[38;5;49m▝[0m[38;5;49m▀[0m[38;5;49m▘[0m[38;5;49m▘[0m[38;5;49m [0m[38;5;49m [0m

v$VERSION"
}

main() {
	
	# Generate Linebreak String
	lb="$(printf "%-${COLUMNS}s")"
	
	arg_handler "$@"

	# Display fancy splash
	echo -e "\e[1m${lb// /=}\e[22m"
	splash
	echo -e "\e[1m${lb// /=}\e[22m"
	
	# If we have no Steam UID from arguments...
	if [ ! "$STEAM_UID" ]; then
		if ! read_config; then
			if [ -t 1 ]; then
				prompt_id
			else
				err "No valid Steam UID"
				exit 1
			fi
		fi

		save_config
		echo -e "\e[1m${lb// /-}\e[22m"
	fi

	echo "STEAM DIR  : $STEAM_DIR"
	echo "TARGET DIR : $TARGET_DIR"
	echo "STEAM UID  : $STEAM_UID"	
	echo -e "\e[1m${lb// /-}\e[22m"


	if [ ! -d "$STEAM_DIR/userdata/$STEAM_UID" ]; then
		err -e "\e[1mInvalid Userdata Directory:\e[22m"
		err "  $STEAM_DIR/userdata/$STEAM_UID"
		exit 1
	fi

	# Directory Where Steam Screenshots Are
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

	# Do The Thing!
	locate_libraries
	echo -e "\e[1m${lb// /-}\e[22m"
	idgames
	mklinks

	exit
}

main "$@"
