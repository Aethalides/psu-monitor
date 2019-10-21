
#!/bin/sh
set -uo pipefail

trap cleanUp SIGHUP SIGINT SIGQUIT SIGILL SIGABRT SIGTERM EXIT

declare -gr __DIR__="$(dirname $(readlink -f "${BASH_SOURCE[0]}"))"

declare -ga TEMPFILES=()

# Emoji to use for positive notifications
declare -gr SLACK_EMOJI_SUCCESS=":hot_pepper:"

# Emoji to use for negative notifications
declare -gr SLACK_EMOJI_FAIL=":skull_and_crossbones:"

# Slack Web-hook for negative notifications
declare -gr SLACK_DEFAULT_URL_FAIL="%SLACK_FAIL_URL%"

# Slack Web-hook for positive notifications
declare -gr SLACK_DEFAULT_URL_SUCCESS="%SLACK_SUCCESS_URL%"

# Slack "From / title"
declare -gr SLACK_USER="%SLACK_USER%"

# JSON template for posting a Slack message. %q = analogous to sprintf's %s
# with the exception that quoting will be applied
declare -gr SLACK_MESSAGE_TEMPLATE='{"username":"%q","text":"%q","icon_emoji":"%q"}'

# format: hours and minutes with leading zeroes and concatenated together
# e.g. 6.30PM becomes 1830
#      6.30AM becomes 0630
#      6.05AM becomes 0605

# see about sending a reminder when we are 
# this time or greater
declare -gr REMINDER_TIME_MIN=1100

# don't send a reminder after this time
declare -gr REMINDER_TIME_MAX=1130

declare -gr NOW_TIME="$(date +%k%M)"

declare -gr REMINDER_POWER_LOCK="/tmp/psu-monitor.reminder-lock"

declare -g COOLDOWN_POWER_LOCK="/tmp/psu-monitor.cooldown-lock"

declare -g COOLDOWN_PERIOD=600 # in seconds

declare -g NOW_TIME_SECS="$(date +%s)"

declare -g COOLDOWN_APPLY=$((NOW_TIME_SECS+COOLDOWN_PERIOD))

declare -gi static_state_pending=0

declare -gr BASE="$(basename "${0}")"

IFS=$'\n'

cleanUp() { 

        local intStatus=$?

        [ -z "${intStatus}" ] && intStatus=0

        if [ "${DEBUG:-0}" -eq 1 ]; then

                printTempFiles

        else

                deleteTempFiles

        fi

        exit ${intStatus}
} 

thePowerTouch() {

        touch "${COOLDOWN_POWER_LOCK}" -t $(              \
                date --date "@${COOLDOWN_APPLY}" "+%y%m%d%H%M" \
        )
}

onPowerCooldown() {

        if [ -f "${COOLDOWN_POWER_LOCK}" ]; then

                local -i locked_at="$(stat -c %X "${COOLDOWN_POWER_LOCK}")"

                if [ ! "${locked_at}" -gt "${NOW_TIME_SECS}" ]; then

                        thePowerTouch

                        return 0
                fi

                return 1

        else

                thePowerTouch

                return 0
        fi

        return 1
}

sendPowerAlert() {

        if onPowerCooldown; then 

                SLACK_EMJOI_OVERRIDE=":electric_plug:" SLACK_USER_OVERRIDE="$(hostname -s)'s PSU Monitor" \
                        sendSlackNotification 0 "WARNING $(hostname -s) has got a power supply problem: \`${1}\`"

        fi
}

sendPowerRemindIfDue() {

        # NOW >= Reminder time, and Reminder time > NOW

        if [ "${NOW_TIME}" -ge "${REMINDER_TIME_MIN}" -a "${REMINDER_TIME_MAX}" -gt "${NOW_TIME}" ]; then

                if [ ! -f "${REMINDER_POWER_LOCK}" ]; then 

                        touch "${REMINDER_POWER_LOCK}"

                        SLACK_EMJOI_OVERRIDE=":electric_plug:" SLACK_USER_OVERRIDE="$(hostname -s)'s PSU Monitor" \
                                sendSlackNotification 1 "$(hostname -s)'s power supply monitor active, everything looking good (\`${1}\`)"
                fi
        fi
}

sendPowerBugReport() {

        if onPowerCooldown; then

                SLACK_EMJOI_OVERRIDE=":electric_plug:" SLACK_USER_OVERRIDE="$(hostname -s)'s PSU Monitor" \
                        sendSlackNotification 0 "WARNING $(hostname -s) has got a power supply problem: \`${1}\`"
        fi
}


# Test if we are zero or positive int
# no sign symbols are allowed, nor are decimal points
isInt() {

        [ 1 -ne $# ] && bug_on "isInt() takes exactly one argument"

        [[ "${1}" =~ ^[0-9]+$ ]]

}

action_on() {

        local action="${1}"

        shift

        if [ 1 -eq "${static_state_pending}" ]; then

                if [ error = "${action}" -o fail = "${action}" ]; then

                        ${action} $*

                else

                        error $*
                fi

                static_state_pending=0

        else

                while [[ $# -gt 0 ]]; do 

                        >&2 echo -e "${BASE}: ERROR: $1"

                        shift

                done
        fi

        exit 1
}

error_on()   { action_on ${FUNCNAME[0]%%_on} $*; }

warning_on() { action_on ${FUNCNAME[0]%%_on} $*; }

bug_on()     { action_on ${FUNCNAME[0]%%_on} $*; }

sendSlackNotification() {

        local datafile=$(getTempFile)

        local emoji="${SLACK_EMOJI_SUCCESS}"

        local slack_url

        [ $# -lt 2 ] && bug_on "${FUNCNAME[0]}() takes 2 or more arguments"

        isInt "${1}" || bug_on "${FUNCNAME[0]}() first argument must be integer"

        [ 0 -eq $1 ] && emoji="${SLACK_EMOJI_FAIL}"

        registerTempFile "${datafile}"

        emoji="${SLACK_EMJOI_OVERRIDE:-${emoji}}"

        # it is possible that we are called before the profile is parsed, so 
        # if the SLACK_CHOSEN_???_URL is not yet set, we'll set it from the
        # default

        if [ ${1} -eq 0 ]; then

                if [ -v "SLACK_CHOSEN_SUCCESS_URL" ]; then 

                        slack_url="${SLACK_CHOSEN_SUCCESS_URL}"

                else

                        slack_url="${SLACK_DEFAULT_URL_SUCCESS}"
                fi

        else

                if [ -v "SLACK_CHOSEN_FAIL_URL" ]; then 

                        slack_url="${SLACK_CHOSEN_FAIL_URL}"

                else

                        slack_url="${SLACK_DEFAULT_URL_FAIL}"
                fi
        fi

        shift

		cat > "${datafile}" <<-CURL
		{"username":"${SLACK_USER_OVERRIDE:-${SLACK_USER}}",
		"text":"$*",
		"icon_emoji":"${emoji}"
		}
		CURL

        if [ 1 -eq "${DEBUG:-0}" ]; then

                echo "Debug active, not sending slack notification"
                echo "If debug was not active, we would be executing this command:"
                echo \                                \
                 curl                                  \
                        -X POST                             \
                        -H 'Content-type: application/json'  \
                        "${slack_url}"                        \
                        -d "@${datafile}"
                echo "----"
                echo "Contents of datafile ${datafile}:"
                cat "${datafile}"

        else

                curl                                  \
                        -X POST                            \
                        -H 'Content-type: application/json' \
                        "${slack_url}"                       \
                        -d "@${datafile}"
        fi

        unlink "${datafile}"
}

getTempFile() {

        mktemp --dry-run
        #echo "/tmp/_$(date +%s.%N)"

}

registerTempFile() {

        while [[ $# -gt 0 ]]; do

                # add to array to clean up later 

                [ -n "${1}" ] && TEMPFILES+=("$1")

                shift

        done
}

unregisterTempFile() {

        local intCount=${#TEMPFILES[@]} arrKeys strKey strFile

        while [[ $# -gt 0  && 0 -lt ${intCount} ]]; do

                if [ -n "$1" ]; then

                        # get the keys present in the array 

                        arrKeys=("${!TEMPFILES[@]}")

                        # now loop over all the keys

                        for strKey in ${arrKeys[@]}; do


                                strFile="${TEMPFILES[$strKey]}"

                                if [ -n "${strFile}" ]; then

                                        if [ "${strFile}" == "$1" ]; then

                                                # found  the one to remove

                                                unset TEMPFILES[$strKey]

                                                ((intCount--))


                                                # do not break here as there could be duplicates in the array

                                        fi
                                fi


                        done

                fi

                shift

        done
}

deleteTempFiles() {

        # if temporary files were requested . . .

        local intCount="${#TEMPFILES[@]}" strFile intStatus=0

        if [ 0 -lt "${intCount}" ]; then 

                for strFile in ${TEMPFILES[@]}; do 

                        if [[ -n "${strFile}" && -f "${strFile}" ]]; then 

                                # file exists, let's remove it

                                unlink "${strFile}" || intStatus=1
                        fi
                done
        fi

        TEMPFILES=()

        return $intStatus
}

printTempFiles() {

        local -i count="${#TEMPFILES[@]}"
        local -i index=1

        echo
        echo "Temporary files used:"
        echo "---------------------"

        if [ 0 -eq "${count}" ]; then

                echo "<None>"

        else

                set - "${TEMPFILES[@]}"

                while [[ $# -gt 0 ]]; do

                        printf "%02d : %s\n" "${index}" "${1}"

                        ((index++))

                        shift
                done

        fi

        echo "---------------------"
        echo 

        [ 0 -lt "${count}" ] && \
                echo -e "NOTE: because debugging is active, these temporary files were not deleted\n"

}

errorcode() {

        local intStatus=1

        # exit status should be first parameter, every thing else is human readable text message
        # so we need at least one parameter

        if [ 0 -lt $# ]; then

                intStatus=$1

                # convert to integer, or zero

                intStatus=$(printf '%d' ${intStatus//[^[:digit:]]/0})

                # set intStatus to 1 if zero, don't touch otherwise

                ((intStatus==0 && intStatus++))

                shift 

                if [[ 0 -eq $# ]]; then 

                        echo >&2 "${BASE}: ERROR: Unknown stop condition reached"

                else

                        while [[ $# -gt 0 ]]; do 

                                echo >&2 "${BASE}: ERROR: $1"

                                shift

                        done
                fi

        else

                error "(BUG): errorcode function expects at least 1 parameter"
        fi

        exit ${intStatus}
}

# prints output to STDERR

dprint(){

        [ $DEBUG -eq 1 ] && while [[ $# -gt 0 ]]; do 

                # Redirect STDOUT to STDERR for duration of command

                >&2 echo -e "${BASE}: $1"

                shift

        done
}

testPower() {

        local reply

        local ipmitool=$(which ipmitool 2>/dev/null)
        
        [ -n "${ipmitool}" ] || error_on "ipmitool is not available on this system. Please install it first"
        
        reply=$(${ipmitool} sdr type 0x8 | "${__DIR__}/psu_status.awk")

        local -i res=$?

        case "${res}" in

                0) 
                        sendPowerRemindIfDue "${reply}" 

                ;;

                2|3|4) 

                        sendPowerAlert "${reply}"

                ;;

                *)

                        sendPowerBugReport "${res}" "${reply}"

                ;;
        esac
}

main() {

	[ 0 -eq "${UID:-1000}" ] || error_on "must be run as root"
	
	( testPower )
}

main