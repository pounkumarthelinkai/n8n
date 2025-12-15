#!/bin/bash
# Script to copy old Supabase backups from old Backblaze account to new one

set -euo pipefail

OLD_ACCOUNT="f0a1ed2b3f4e"
OLD_KEY="00308f1d8da0e528b626e171dc5cbac1b1facb9ae4"
OLD_REMOTE="b2supabase_old"
OLD_PATH="shiva-engineering-services/supabase-daily-backup"

NEW_REMOTE="b2supabase"
NEW_PATH="supabasedaillybackup/supabase-daily-backup"

echo "Creating temporary rclone remote for old account..."
rclone config create "${OLD_REMOTE}" b2 account="${OLD_ACCOUNT}" key="${OLD_KEY}" hard_delete=true versions=false

echo "Listing old backups..."
rclone lsd "${OLD_REMOTE}:${OLD_PATH}" || {
    echo "Error: Could not access old backups. The old account may no longer be accessible."
    exit 1
}

echo "Copying old backups to new account..."
rclone copy "${OLD_REMOTE}:${OLD_PATH}" "${NEW_REMOTE}:${NEW_PATH}" --progress

echo "Verifying copied backups..."
rclone lsd "${NEW_REMOTE}:${NEW_PATH}"

echo "Removing temporary old remote..."
rclone config delete "${OLD_REMOTE}"

echo "Backup copy completed successfully!"

