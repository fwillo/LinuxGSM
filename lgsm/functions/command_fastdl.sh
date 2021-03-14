#!/bin/bash
# LinuxGSM command_fastdl.sh module
# Author: Daniel Gibbs
# Contributors: http://linuxgsm.com/contrib
# Website: https://linuxgsm.com
# Description: Creates a FastDL directory.

commandname="FASTDL"
commandaction="Fastdl"
functionselfname="$(basename "$(readlink -f "${BASH_SOURCE[0]}")")"
fn_firstcommand_set

check.sh

# Directories.
if [ -z "${webdir}" ]; then
	webdir="${rootdir}/public_html"
fi
fastdldir="${webdir}/fastdl2"
addonsdir="${systemdir}/addons"
# Server lua autorun dir, used to autorun lua on client connect to the server.
luasvautorundir="${systemdir}/lua/autorun/server"
luafastdlfile="lgsm_cl_force_fastdl.lua"
luafastdlfullpath="${luasvautorundir}/${luafastdlfile}"

# printf throws errors if locale is different from english
LC_NUMERIC="en_US.UTF-8"

# Check if bzip2 is installed.
if [ ! "$(command -v bzip2 2>/dev/null)" ]; then
	fn_print_fail "bzip2 is not installed"
	fn_script_log_fatal "bzip2 is not installed"
	core_exit.sh
fi

# Header
fn_print_header
echo -e "More info: https://docs.linuxgsm.com/commands/fastdl"
echo -e ""

# Prompts user for FastDL creation settings.
echo -e "${commandaction} setup"
echo -e "================================="

# Garry's Mod Specific.
if [ "${shortname}" == "gmod" ]; then
	# Prompt for download enforcer, which is using a .lua addfile resource generator.
	if fn_prompt_yn "Force clients to download files?" Y; then
		luaresource="on"
		fn_script_log_info "Force clients to download files: YES"
	else
		luaresource="off"
		fn_script_log_info "Force clients to download filesr: NO"
	fi
fi

# Clears any fastdl directory content.
fn_clear_old_fastdl(){
	# Clearing old FastDL.
	if [ -d "${fastdldir}" ]; then	
		# Prompt for clearing old files if directory was already here.
		fn_print_warning_nl "FastDL directory already exists."
		echo -e "${fastdldir}"
		echo -e ""

		if fn_prompt_yn "Rebuild complete FastDL directory?" N; then
			fn_script_log_info "Rebuild existing directory: YES"

			rm -fR "${fastdldir:?}"
			exitcode=$?
			if [ "${exitcode}" != 0 ]; then
				fn_print_fail_eol_nl
				fn_script_log_fatal "Clearing existing FastDL directory ${fastdldir}"
				core_exit.sh
			else
				fn_print_ok_eol_nl
				fn_script_log_pass "Clearing existing FastDL directory ${fastdldir}"
			fi
		fi
	fi
}

fn_fastdl_dirs(){
	# Check and create directories.
	if [ ! -d "${webdir}" ]; then
		echo -en "creating web directory ${webdir}..."
		mkdir -p "${webdir}"
		exitcode=$?
		if [ "${exitcode}" != 0 ]; then
			fn_print_fail_eol_nl
			fn_script_log_fatal "Creating web directory ${webdir}"
			core_exit.sh
		else
			fn_print_ok_eol_nl
			fn_script_log_pass "Creating web directory ${webdir}"
		fi
	fi

	if [ ! -d "${fastdldir}" ]; then
		echo -en "creating fastdl directory ${fastdldir}..."
		mkdir -p "${fastdldir}"
		exitcode=$?
		if [ "${exitcode}" != 0 ]; then
			fn_print_fail_eol_nl
			fn_script_log_fatal "Creating fastdl directory ${fastdldir}"
			core_exit.sh
		else
			fn_print_ok_eol_nl
			fn_script_log_pass "Creating fastdl directory ${fastdldir}"
		fi
	fi
}

# Using this gist https://gist.github.com/agunnerson-ibm/efca449565a3e7356906
fn_human_readable_file_size(){
	local abbrevs=(
		$((1 << 60)):ZB
		$((1 << 50)):EB
		$((1 << 40)):TB
		$((1 << 30)):GB
		$((1 << 20)):MB
		$((1 << 10)):KB
		$((1)):bytes
	)

	local bytes="${1}"
	local precision="${2}"

	if [[ "${bytes}" == "1" ]]; then
		echo -e "1 byte"
	else
		for item in "${abbrevs[@]}"; do
			local factor="${item%:*}"
			local abbrev="${item#*:}"
			if [[ "${bytes}" -ge "${factor}" ]]; then
					size=$(bc -l <<< "${bytes} / ${factor}")
					printf "%.*f %s\n" "${precision}" "${size}" "${abbrev}"
					break
				fi
			done
		fi
}

fn_fastdl_preview_newfiles() {
	#$1: 		directory 
	#$2: 		allowed_extention
	#return: 	fileswc
	
	# get all files of $1, in case of 1="", escape beginning "./" with sed resulting from find with no given folder
	fastdl_newfiles=$(find $1 -type f \( -iname "$2" -a ! -iwholename "*/workshop*" \) | sed s+^\./++g)

	# Are there any files? Need to check "-z", otherwise sha1sum reads from stdin infinitely
	if [ ! -z "${fastdl_newfiles}" ]; then
		echo "${fastdl_newfiles}" >> ${tmpdir}/fastdl_files.txt
		fastdl_newfiles=$(sha1sum ${fastdl_newfiles})

		# filter all files of $2 and also placed in $1; if $1="", because of sed in ${fastdl_newfiles}
		# result will be the same from given ERE in grep
		fastdl_files_available=$(grep -E "${directory}/.${allowed_extention}" ${fastdldir}/checksum.txt)
		exitcode=$?

		# Check for files only in ${fastdl_newfiles}
		if [ "${exitcode}" == 0 ]; then
			fastdl_newfiles=$(comm -23 <(echo "${fastdl_newfiles}" | sort) <(echo "${fastdl_files_available}" | sort))
		fi
	
		# Are there any files left after comparision?
		if [ ! -z "${fastdl_newfiles}" ]; then
			echo -e "${fastdl_newfiles}" >> ${tmpdir}/fastdl_files_to_compress.txt
			return $(echo -e "${fastdl_newfiles}" | wc -l)
		else
			return 0
		fi
	else
		return 0
	fi

}

# Provides info about the fastdl directory content and prompts for confirmation.
fn_fastdl_preview(){
	cd "${systemdir}" || exit

	# Remove any file list.
	compgen -G "${tmpdir}/fastdl*.txt" > /dev/null 
	exitcode=$?
	if [ "${exitcode}" == 0 ]; then
		rm -f ${tmpdir:?}/fastdl*.txt
	fi

	if [ ! -f "${fastdldir}/checksum.txt" ]; then
		touch "${fastdldir}/checksum.txt"
	fi	

	if [ ! -f "${tmpdir}/fastdl_files_to_compress.txt" ]; then
		touch "${tmpdir}/fastdl_files_to_compress.txt"
	fi


	echo -e "Analysing new files"
	fn_script_log_info "Analysing new files"
	# Garry's Mod
	if [ "${shortname}" == "gmod" ]; then
		allowed_extentions_array=( "*.ain" "*.bsp" "*.mdl" "*.mp3" "*.ogg" "*.otf" "*.pcf" "*.phy" "*.png" \
					   "*.svg" "*.vtf" "*.vmt" "*.vtx" "*.vvd" "*.ttf" "*.wav" )
		for allowed_extention in "${allowed_extentions_array[@]}"; do
			fn_fastdl_preview_newfiles "" "${allowed_extention}"
			fileswc=$?

			printf "\r\033[Kgathering %5s : %6i... " "${allowed_extention}" ${fileswc}
			if [ ${fileswc} != 0 ]; then
				fn_print_ok_eol_nl
			else
				fn_print_info_eol_nl
			fi

		done

	# Source Engine
	else
		fastdl_directories_array=( "maps" "materials" "models" "particles" "sound" "resources" )
		for directory in "${fastdl_directories_array[@]}"; do
			if [ -d "${directory}" ]; then
				if [ "${directory}" == "maps" ]; then
					local allowed_extentions_array=( "*.bsp" "*.ain" "*.nav" "*.jpg" "*.txt" )
				elif [ "${directory}" == "materials" ]; then
					local allowed_extentions_array=( "*.vtf" "*.vmt" "*.vbf" "*.png" "*.svg" )
				elif [ "${directory}" == "models" ]; then
					local allowed_extentions_array=( "*.vtx" "*.vvd" "*.mdl" "*.phy" "*.jpg" "*.png" "*.vmt" "*.vtf" )
				elif [ "${directory}" == "particles" ]; then
					local allowed_extentions_array=( "*.pcf" )
				elif [ "${directory}" == "sound" ]; then
					local allowed_extentions_array=( "*.wav" "*.mp3" "*.ogg" )
				fi

				for allowed_extention in "${allowed_extentions_array[@]}"; do
					fn_fastdl_preview_newfiles "${directory}" "${allowed_extention}"
					fileswc=$?

					printf "\r\033[Kgathering %-10s %5s : %6i... " ${directory} "${allowed_extention}" ${fileswc}
					if [ ${fileswc} != 0 ]; then
						fn_print_ok_eol_nl
					else
						fn_print_info_eol_nl
					fi

				done
			fi
		done
	fi

	echo -e "================================="
	if [ -f "${tmpdir}/fastdl_files_to_compress.txt" ]; then
		totalfiles=$(wc -l < "${tmpdir}/fastdl_files_to_compress.txt")
		if [ ${totalfiles} == 0 ]; then
			echo -ne "No new files registered. "
			fn_print_info_nl " No new files registered. Closing... "
			fn_script_log_info "No new files registered. Closing... "
			core_exit.sh
		else
			echo -e "Calculating total file size..."
			fn_sleep_time
			# Calculates total file size.
			while read -r dufile; do
				filesize=$(stat -c %s "${dufile#*  }")
				filesizetotal=$(( filesizetotal+filesize ))
				exitcode=$?
				if [ "${exitcode}" != 0 ]; then
					fn_print_fail_eol_nl
					fn_script_log_fatal "Calculating total file size."
					core_exit.sh
				fi
			done < "${tmpdir}/fastdl_files_to_compress.txt"
		fi
	else
		fn_print_fail_eol_nl "Generating file list"
		fn_script_log_fatal "Generating file list."
		core_exit.sh
	fi
	echo -e "About to compress ${totalfiles} files, total size $(fn_human_readable_file_size ${filesizetotal} 0)"
	fn_script_log_info "${totalfiles} files, total size $(fn_human_readable_file_size ${filesizetotal} 0)"
	if ! fn_prompt_yn "Continue?" Y; then
		fn_script_log "User exited"
		core_exit.sh
	fi
}

# Builds Garry's Mod fastdl directory content.
fn_fastdl_gmod(){
	# Correct addons directory structure for FastDL.
	if [ -d "${fastdldir}/addons" ]; then
		echo -en "updating addons file structure..."
		cp -Rf "${fastdldir}"/addons/*/* "${fastdldir}"
		exitcode=$?
		if [ "${exitcode}" != 0 ]; then
			fn_print_fail_eol_nl
			fn_script_log_fatal "Updating addons file structure"
			core_exit.sh
		else
			fn_print_ok_eol_nl
			fn_script_log_pass "Updating addons file structure"
		fi
		# Clear addons directory in fastdl.
		echo -en "clearing addons dir from fastdl dir..."
		fn_sleep_time
		rm -fR "${fastdldir:?}/addons"
		exitcode=$?
		if [ "${exitcode}" != 0 ]; then
			fn_print_fail_eol_nl
			fn_script_log_fatal "Clearing addons dir from fastdl dir"
			core_exit.sh
		else
			fn_print_ok_eol_nl
			fn_script_log_pass "Clearing addons dir from fastdl dir"
		fi
	fi

	# Correct content that may be into a lua directory by mistake like some darkrpmodification addons.
	if [ -d "${fastdldir}/lua" ]; then
		echo -en "correcting DarkRP files..."
		fn_sleep_time
		cp -Rf "${fastdldir}/lua/"* "${fastdldir}"
		exitcode=$?
		if [ "${exitcode}" != 0 ]; then
			fn_print_fail_eol_nl
			fn_script_log_fatal "Correcting DarkRP files"
			core_exit.sh
		else
			fn_print_ok_eol_nl
			fn_script_log_pass "Correcting DarkRP files"
		fi
	fi

	if [ -f "${tmpdir}/fastdl_files_to_compress.txt" ]; then
		totalfiles=$(wc -l < "${tmpdir}/fastdl_files_to_compress.txt")
		# Calculates total file size.
		while read -r dufile; do
			filesize=$(du -b "${dufile#*  }" | awk '{ print $1 }')
			filesizetotal=$((filesizetotal + filesize))
		done <"${tmpdir}/fastdl_files_to_compress.txt"
	fi
}


# Builds the fastdl directory content.
fn_fastdl_build(){
	# Copy all needed files for FastDL.
	echo -e "\n================================="
	echo -e "copying files to ${fastdldir}"
	fn_script_log_info "Copying files to ${fastdldir}"

	sumfileswc=$(wc -l < ${tmpdir}/fastdl_files_to_compress.txt)
	fileswc=0	
	while read -r fastdlfile; do 
		((fileswc++))

		relfilepath=${fastdlfile#*  }
		printf "\r\033[Kcopying %6i/%-6i: %s... " ${fileswc} ${sumfileswc} ${relfilepath}
		cp --parents "${relfilepath}" "${fastdldir}"
		exitcode=$?
		if [ "${exitcode}" != 0 ]; then
			fn_print_fail_eol_nl
			fn_script_log_fatal "Copying ${relfilepath} > ${fastdldir}"
			core_exit.sh
		else
			fn_script_log_pass "Copying ${relfilepath} > ${fastdldir}"
		fi

		grep "${relfilepath}" ${fastdldir}/checksum.txt &> /dev/null
		exitcode=$?
		if [ $exitcode == 0 ]; then
			sed -i "s+.*${relfilepath}.*+${fastdlfile}+" ${fastdldir}/checksum.txt
		else
			echo "${fastdlfile}" >> ${fastdldir}/checksum.txt
		fi

	done < ${tmpdir}/fastdl_files_to_compress.txt
	fn_print_ok_eol_nl

	if [ "${shortname}" == "gmod" ]; then
		fn_fastdl_gmod
		fn_fastdl_gmod_dl_enforcer
	fi
}

# Generate lua file that will force download any file into the FastDL directory.
fn_fastdl_gmod_dl_enforcer(){
	# Clear old lua file.
	if [ -f "${luafastdlfullpath}" ]; then
		echo -en "removing existing download enforcer: ${luafastdlfile}..."
		rm -f "${luafastdlfullpath:?}"
		exitcode=$?
		if [ "${exitcode}" != 0 ]; then
			fn_print_fail_eol_nl
			fn_script_log_fatal "Removing existing download enforcer ${luafastdlfullpath}"
			core_exit.sh
		else
			fn_print_ok_eol_nl
			fn_script_log_pass "Removing existing download enforcer ${luafastdlfullpath}"
		fi
	fi
	# Generate new one if user said yes.
	if [ "${luaresource}" == "on" ]; then
		echo -en "creating new download enforcer: ${luafastdlfile}..."
		touch "${luafastdlfullpath}"
		# Read all filenames and put them into a lua file at the right path.
		while read -r line; do
			echo -e "resource.AddFile( \"${line%.bz2}\" )" >> "${luafastdlfullpath}"
		done < <(find "${fastdldir:?}" \( -type f ! -name "checksum.txt" \) -printf '%P\n')
		exitcode=$?
		if [ "${exitcode}" != 0 ]; then
			fn_print_fail_eol_nl
			fn_script_log_fatal "Creating new download enforcer ${luafastdlfullpath}"
			core_exit.sh
		else
			fn_print_ok_eol_nl
			fn_script_log_pass "Creating new download enforcer ${luafastdlfullpath}"
		fi
	fi
}

# Compresses FastDL files using bzip2.
fn_fastdl_bzip2(){
	echo -e "\n================================="
	echo -e "Compressing files in ${fastdldir}..."
	
	filestocompress=$(find "${fastdldir:?}" \( -type f ! -name "*.bz2" ! -name "checksum.txt" \))
	fileswc=0
	sumfileswc=$(echo "${filestocompress}" | wc -l)
	while read -r filetocompress; do
		((fileswc++))

		printf "\r\033[KCompressing %6i/%-6i: %s... " ${fileswc} ${sumfileswc} "${filetocompress#"${fastdldir}/"}"
		bzip2 -f "${filetocompress}"
		exitcode=$?
		if [ "${exitcode}" != 0 ]; then
			fn_print_fail_eol_nl
			fn_script_log_fatal "Compressing ${filetocompress}"
			core_exit.sh
		else
			fn_script_log_pass "Compressing ${filetocompress}"
		fi
	done < <(echo "${filestocompress}")
	fn_print_ok_eol_nl
}

# Run functions.
fn_clear_old_fastdl
fn_fastdl_dirs
fn_fastdl_preview
fn_fastdl_build
fn_fastdl_bzip2

# Finished message.
echo -e "\n================================="
echo -e "FastDL files are located in:"
echo -e "${fastdldir}"
echo -e "FastDL completed"
fn_script_log_info "FastDL completed"

core_exit.sh
