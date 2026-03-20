#!/bin/bash
set -e

SUBMISSIONS_DIR="/root/.edgar/submissions"

if [ ! -d "$SUBMISSIONS_DIR" ] || [ -z "$(ls -A "$SUBMISSIONS_DIR" 2>/dev/null)" ]; then
    echo "Downloading SEC submissions data (one-time, ~500MB)..."
    python -c "from edgar.storage._local import download_submissions; download_submissions(disable_progress=True)"
    echo "Download complete."
else
    echo "SEC submissions data found, skipping download."
fi

exec "$@"
