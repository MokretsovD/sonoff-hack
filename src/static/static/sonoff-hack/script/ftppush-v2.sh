#!/bin/ash

CONF_FILE="etc/system.conf"

SONOFF_HACK_PREFIX="/mnt/mmc/sonoff-hack"

get_config() {
	key=$1
	grep -w $1 $SONOFF_HACK_PREFIX/$CONF_FILE | cut -d "=" -f2
}
# Setup env.
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/mnt/mmc/sonoff-hack/lib
export PATH=$PATH:/mnt/mmc/sonoff-hack/bin:/mnt/mmc/sonoff-hack/sbin:/mnt/mmc/sonoff-hack/usr/bin:/mnt/mmc/sonoff-hack/usr/sbin

# Script Configuration.
FOLDER_TO_WATCH="/mnt/mmc/alarm_record"
FOLDER_MINDEPTH="1"
FILE_WATCH_PATTERN="*.mp4"
SKIP_UPLOAD_TO_FTP="0"
LOCK_PID_FILE="/mnt/mmc/sonoff-hack/ftp-upload-lock.pid"

# Runtime Variables.
SCRIPT_FULLFN="ftppush.sh"
SCRIPT_NAME="ftppush"
LOGFILE="/tmp/${SCRIPT_NAME}.log"
LOG_MAX_LINES="200"
#
# -----------------------------------------------------
# -------------- START OF FUNCTION BLOCK --------------
# -----------------------------------------------------
checkFiles() {
	
	FTP_FILE_DELETE_AFTER_UPLOAD="$(get_config FTP_FILE_DELETE_AFTER_UPLOAD)"

	logAdd "[INFO] checkFiles"

	# Search for new files.
	if [ -f "/usr/bin/sort" ]; then
		# Default: Optimized for busybox
		L_FILE_LIST="$(find "${FOLDER_TO_WATCH}" -mindepth ${FOLDER_MINDEPTH} -mmin +0 -type f \( -name "${FILE_WATCH_PATTERN}" \) | sort -k 1 -n)"
	else
		# Alternative: Unsorted output
		L_FILE_LIST="$(find "${FOLDER_TO_WATCH}" -mindepth ${FOLDER_MINDEPTH} -mmin +0 -type f \( -name "${FILE_WATCH_PATTERN}" \))"
	fi
	if [ -z "${L_FILE_LIST}" ]; then
		logAdd "[INFO] checkFiles: No files to process. Exiting"
		return 0
	fi

	echo "${L_FILE_LIST}" | while read file; do
		if (! uploadToFtp -- "${file}"); then
			logAdd "[ERROR] checkFiles: uploadToFtp FAILED - [${file}]."
			continue
		fi
		logAdd "[INFO] checkFiles: uploadToFtp SUCCEEDED - [${file}]."
		if [ "${FTP_FILE_DELETE_AFTER_UPLOAD}" == "yes" ]; then
			logAdd "[INFO] checkFiles: Removing File - [${file}]."
			rm -f "${file}"
		else
			logAdd "[INFO] checkFiles: NOT removing File - [${file}]."
		fi
	done
	#
	# Delete empty sub directories
	if [ ! -z "${FOLDER_TO_WATCH}" ]; then
		deleteEmptyFolders
	fi
	#
	return 0
}

deleteEmptyFolders() {
	L_FOLDER_LIST="$(find "${FOLDER_TO_WATCH}" -mindepth ${FOLDER_MINDEPTH} -mmin +70 -type d)"

	echo "${L_FOLDER_LIST}" | while read direct; do
		if ([[ -z "$(find ${direct} -mindepth 1)" ]]); then
			logAdd "[INFO] checkFiles: deleting empty folder - [${direct}]."
			rm -rf ${direct}
		fi
	done
}

lbasename() {
	echo "${1}" | sed "s/.*\///"
}

lgparentdir() {
	echo "${1}" | $SONOFF_HACK_PREFIX/usr/bin/xargs -I{} dirname {} | $SONOFF_HACK_PREFIX/usr/bin/xargs -I{} dirname {} | grep -o '[^/]*$'
}

lparentdir() {
	echo "${1}" | $SONOFF_HACK_PREFIX/usr/bin/xargs -I{} dirname {} | grep -o '[^/]*$'
}

logAdd() {
	TMP_DATETIME="$(date '+%Y-%m-%d [%H-%M-%S]')"
	TMP_LOGSTREAM="$(tail -n ${LOG_MAX_LINES} ${LOGFILE} 2>/dev/null)"
	echo "${TMP_LOGSTREAM}" >"$LOGFILE"
	echo "${TMP_DATETIME} $*" >>"${LOGFILE}"
	echo "${TMP_DATETIME} $*"
	return 0
}

lstat() {
	if [ -d "${1}" ]; then
		ls -a -l -td "${1}" | awk '{k=0;for(i=0;i<=8;i++)k+=((substr($1,i+2,1)~/[rwx]/) \
				 *2^(8-i));if(k)printf("%0o ",k);print}' |
			cut -d " " -f 1
	else
		ls -a -l "${1}" | awk '{k=0;for(i=0;i<=8;i++)k+=((substr($1,i+2,1)~/[rwx]/) \
				 *2^(8-i));if(k)printf("%0o ",k);print}' |
			cut -d " " -f 1
	fi
}

uploadToFtp() {
	# Consts.
	FTP_HOST="$(get_config FTP_HOST)"
	FTP_DIR="$(get_config FTP_DIR)"
	FTP_DIR_TREE="$(get_config FTP_DIR_TREE)"
	FTP_USERNAME="$(get_config FTP_USERNAME)"
	FTP_PASSWORD="$(get_config FTP_PASSWORD)"
	#
	# Variables.
	UTF_FULLFN="${2}"
	FTP_DIR_DAY="$(lgparentdir ${UTF_FULLFN})"
	FTP_DIR_HOUR="$(lparentdir ${UTF_FULLFN})"
	#
	if [ "${SKIP_UPLOAD_TO_FTP}" = "1" ]; then
		logAdd "[INFO] uploadToFtp skipped due to SKIP_UPLOAD_TO_FTP == 1."
		return 1
	fi
	#
	if [ ! -z "${FTP_DIR}" ]; then
		# Create directory on FTP server
		echo -e "USER ${FTP_USERNAME}\r\nPASS ${FTP_PASSWORD}\r\nmkd ${FTP_DIR}\r\nquit\r\n" | nc -w 5 ${FTP_HOST} 21 | grep "${FTP_DIR}"
		FTP_DIR="${FTP_DIR}/"
	fi
	#
	if [ "${FTP_DIR_TREE}" == "yes" ]; then
		if [ ! -z "${FTP_DIR_DAY}" ]; then
			# Create day directory on FTP server
			echo -e "USER ${FTP_USERNAME}\r\nPASS ${FTP_PASSWORD}\r\nmkd ${FTP_DIR}/${FTP_DIR_DAY}\r\nquit\r\n" | nc -w 5 ${FTP_HOST} 21 | grep "${FTP_DIR_DAY}"
			FTP_DIR_DAY="${FTP_DIR_DAY}/"
		fi
		if [ ! -z "${FTP_DIR_HOUR}" ]; then
			# Create hour directory on FTP server
			echo -e "USER ${FTP_USERNAME}\r\nPASS ${FTP_PASSWORD}\r\nmkd ${FTP_DIR}/${FTP_DIR_DAY}/${FTP_DIR_HOUR}\r\nquit\r\n" | nc -w 5 ${FTP_HOST} 21 | grep "${FTP_DIR_HOUR}"
			FTP_DIR_HOUR="${FTP_DIR_HOUR}/"
		fi
	fi
	#
	if [ ! -f "${UTF_FULLFN}" ]; then
		echo "[ERROR] uploadToFtp: File not found."
		return 1
	fi
	#
	if [ "${FTP_DIR_TREE}" == "yes" ]; then
		logAdd "[INFO] uploading file to ${FTP_DIR}${FTP_DIR_DAY}${FTP_DIR_HOUR}$(lbasename "${UTF_FULLFN}")"
		if (! ftpput -u "${FTP_USERNAME}" -p "${FTP_PASSWORD}" "${FTP_HOST}" "${FTP_DIR}${FTP_DIR_DAY}${FTP_DIR_HOUR}$(lbasename "${UTF_FULLFN}")" "${UTF_FULLFN}"); then
			logAdd "[ERROR] uploadToFtp: ftpput FAILED."
			return 1
		fi
	else
		logAdd "[INFO] uploading file to ${FTP_DIR}$(lbasename "${UTF_FULLFN}")"
		if (! ftpput -u "${FTP_USERNAME}" -p "${FTP_PASSWORD}" "${FTP_HOST}" "${FTP_DIR}$(lbasename "${UTF_FULLFN}")" "${UTF_FULLFN}"); then
			logAdd "[ERROR] uploadToFtp: ftpput FAILED."
			return 1
		fi
	fi
	#
	# Return SUCCESS.
	return 0
}

doFTPCopy() {
	logAdd "[INFO] === STARTING IMAGE FOLDER PROCESSING ==="

	# Check if folder exists.
	if [ ! -d "${FOLDER_TO_WATCH}" ]; then
		mkdir -p "${FOLDER_TO_WATCH}"
	fi
	#
	# Ensure correct file permissions.
	if (! lstat "${FOLDER_TO_WATCH}/" | grep -q "^755$"); then
		logAdd "[WARN] Adjusting folder permissions to 0755 ..."
		chmod -R 0755 "${FOLDER_TO_WATCH}"
	fi
	#
	if [[ $(get_config FTP_UPLOAD) == "yes" ]]; then
		checkFiles
	fi

	return 0
}
# ---------------------------------------------------
# -------------- END OF FUNCTION BLOCK --------------
# ---------------------------------------------------
#

trap "rm -f ${LOCK_PID_FILE}" EXIT

doFTPCopy
