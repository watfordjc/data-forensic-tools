data-forensic-tools
===================

A suite of forensic extraction and verification tools designed for auditable data recovery.

## Modules

### [SMS Extraction](./adb/texts/extract-sms.sh)
- **Source:** Android Content Providers (`content://sms`)
- **Verification:** GPG Detached Signatures & RFC 3161 Trusted Timestamps.
- **Output:** ISO-8601 JSON (Millisecond precision).

### [Firefox Android Backup](https://github.com/watfordjc/firefox-android-backup-restore)
- **Source:** External Submodule (Rob--W)
- **Purpose:** Recovery of `places.sqlite` and session data from Android Firefox.

## Environment Setup
Run `./setup_env.sh` to configure Git hooks, check dependencies (adb, jq, openssl), and initialize submodules.
