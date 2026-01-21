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
	echo "Call ID  : ${ID}"
	echo
	echo "--- Command ---"
	CMD='adb shell "content query --uri content://call_log/calls/'${ID}'"'
	echo "$CMD"
	LOGDATA=$(eval "$CMD" | sed "1 s#^Row: [0-9]* ##")
} > "$LOG_FILE"

{
echo "$LOGDATA" | jq -Rs --arg id "$ID" '
[
    split(", ")[] |
    select(contains("=")) |
    sub("^Row: [0-9]+ "; "") |
    capture("(?<k>[^=]+)=(?<v>.*)") |
    {
      key: (.k | sub("^\\s+"; "")),
      value: (
	if (.v == "NULL") then null
	elif (.k == "number" or .k == "normalized_number" or .k == "phone_account_address" or .k == "subject" or .k == "call_screening_app_name" or .k == "photo_uri" or .k == "transcription" or .k == "name" or .k == "data1" or .k == "data2" or .k == "data3" or .k == "data4" or .k == "numberlabel" or .k == "composer_photo_uri" or .k == "lookup_uri" or .k == "voicemail_uri" or .k == "matched_number" or .k == "location" or .k == "asserted_display_name" or .k == "call_screening_component_name")
	then .v
	else (.v | try tonumber)
	end
	)
    }
] |
  reduce .[] as $item (
    {"_id": ($id | tonumber)};
    .[$item.key] = $item.value
  ) |
  .date as $date | .last_modified as $last_modified | . + {
  "date_iso": (($date / 1000 | strftime("%Y-%m-%dT%H:%M:%S")) + "." + (($date % 1000 + 1000 | tostring) | .[1:]) + "Z"),
  "last_modified_iso": (($last_modified / 1000 | strftime("%Y-%m-%dT%H:%M:%S")) + "." + (($last_modified % 1000 + 1000 | tostring) | .[1:]) + "Z")
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
