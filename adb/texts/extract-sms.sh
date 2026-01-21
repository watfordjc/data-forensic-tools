#!/bin/bash

if ! test "$1" -gt 0 2>/dev/null; then
	echo "Usage: $0 _id"
	exit 1
fi

DIR="$(pwd)"
cd "$DIR" || exit 1

ID="$1"
LOG_FILE="${ID}.log"
JSON_FILE="${ID}.json"
CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"

TIMESTAMP=$(date -u -Ins)
DEVICES=$(adb devices -l | grep -v 'List of')

GPG_UID="hostmaster@johncook.co.uk"
TIMESTAMP_URL="http://timestamp.digicert.com"

if [ -z "$DEVICES" ]; then
	echo "Error: No connected Android devices." >&2
	exit 1
elif [ ! -f "$CA_BUNDLE" ]; then
	echo "Error: Certificate bundle not found." >&2
	exit 1
fi

{
	echo "--- Script Run Information ---"
	echo "Timestamp   : ${TIMESTAMP}"
	echo "Device Info : ${DEVICES}"
	echo "Message ID  : ${ID}"
	echo
	echo "--- Metadata Command ---"
	CMD='adb shell "content query --uri content://sms/'${ID}'" --projection "thread_id,address,person,date,date_sent,protocol,read,status,type,reply_path_present,subject,service_center,locked,error_code,sub_id,creator,seen,deletable,sim_slot,sim_imsi,hidden,group_id,group_type,delivery_date,app_id,msg_id,callback_number,reserved,pri,teleservice_id,link_url,svc_cmd,svc_cmd_content,roam_pending,spam_report,secret_mode,safe_message,favorite,d_rpt_cnt,using_mode,from_address,announcements_subtype,announcements_scenario_id,device_name,correlation_tag,object_id,cmc_prop,bin_info,re_original_key,re_recipient_address,re_content_uri,re_content_type,re_file_name,re_type,re_count_info,decorate_bubble_value,spam_type,block_filtered_status,re_count_info_custom_reaction,predefined_id,is_satellite,group_cotag"'
	echo "$CMD"
	METADATA=$(eval "$CMD")
	echo
	echo "--- Body Command ---"
	CMD='adb shell "content query --uri content://sms/'${ID}'" --projection body | sed "1 s#^Row: [0-9]* body=##"'
	echo "$CMD"
	echo
	BODY_RAW=$(eval "$CMD")
	BODY_HASH=$(echo "$BODY_CLEAN" | sha256sum | awk '{print $1}')
	echo "--- Body Hash ---"
	echo "SHA2-256: $BODY_HASH"
} > "$LOG_FILE"
{
echo "$METADATA" | jq -Rs --arg id "$ID" --arg body "$BODY_RAW" '
  [
    split(", ")[] |
    select(contains("=")) |
    sub("^Row: [0-9]+ "; "") |
    capture("(?<k>[^=]+)=(?<v>.*)") |
    {
      key: (.k | sub("^\\s+"; "")),
      value: (
	if (.v == "NULL") then null
	elif (.k == "sim_imsi") then (.v | .[0:5] + "XXXXXXXXXX")
	elif (.k == "address" or .k == "service_center" or .k == "from_address" or .k == "recipient_address" or .k == "re_recipient_address" or .k == "device_name" or .k == "link_url" or .k == "re_content_uri")
	then .v
	else (.v | try tonumber)
	end
	)
    }
  ] |
  reduce .[] as $item (
    {"_id": ($id | tonumber), "body": $body};
    .[$item.key] = $item.value
  ) |
  .date as $date | .date_sent as $date_sent | . + {
  "date_iso": (($date / 1000 | strftime("%Y-%m-%dT%H:%M:%S")) + "." + (($date % 1000 + 1000 | tostring) | .[1:]) + "Z"),
  "date_sent_iso": (($date_sent / 1000 | strftime("%Y-%m-%dT%H:%M:%S"))  + "." + (($date_sent % 1000 + 1000 | tostring) | .[1:]) + "Z")
}
' | jq .
} > "$JSON_FILE"

{
echo
echo "--- File SHA2-256 Hashsums ---"
if [ ! -f "$JSON_FILE" ]; then
	echo "Error: JSON file not created" >&2
	exit 1
else
	sha256sum "$0"
	sha256sum "$JSON_FILE"
fi
	echo
	echo "--- File Signing and Timestamping ---"
	echo "Signing ${JSON_FILE} using GPG uid ${GPG_UID} at $(date -u -Ins)"
	gpg --local-user "${GPG_UID}" --armor --detach-sign "${JSON_FILE}"
	echo "Sigature file: ${JSON_FILE}.asc (SHA2-256: $(sha256sum """${JSON_FILE}.asc""" | awk '{print $1}'))"
	echo "Timestamping ${JSON_FILE}.asc using ${TIMESTAMP_URL}"
	openssl ts -query -data "$ID.json.asc" -sha256 -cert -out "$ID.json.asc.tsq"
	curl -s -H "Content-Type: application/timestamp-query" --data-binary "@$ID.json.asc.tsq" "$TIMESTAMP_URL" > "$ID.json.asc.tsr"
	TS_DATE=$(openssl ts -reply -in "$ID.json.asc.tsr" -text | grep "Time stamp:" | sed 's/Time stamp: //')
	echo
	echo "--- RFC 3161 Trusted Timestamp ---"
	echo "TSA Service   : ${TIMESTAMP_URL}"
	echo "TSA Token      : ${ID}.json.asc.tsr"
	echo "Trusted Time   : ${TS_DATE}"
	echo "Verification   : $(openssl ts -verify -data """${ID}.json.asc""" -in """${ID}.json.asc.tsr""" -CAfile """${CA_BUNDLE}""" 2>/dev/null | grep -o 'Verification: OK')"
} >> "$LOG_FILE"
gpg --local-user "$GPG_UID" --armor --detach-sign "$LOG_FILE"
#done;
