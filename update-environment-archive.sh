#!/bin/bash

# Was the script sourced?
if ! (return 0 2>/dev/null); then
	echo "$0 must be sourced, not executed!" >&2
	exit 1
fi

# Check if conda is available
if ! declare -f conda > /dev/null; then
	echo "conda was not enabled properly" >&2
	return
fi

# Check if there are uncommitted changed
git status --porcelain > /dev/null || return
git lfs status --porcelain > /dev/null || return
if [ $(git status --porcelain | wc -l) != 0 ] || [ $(git lfs status --porcelain | wc -l) != 0 ]; then
	echo "Working copy contains uncommitted changes" >&2
	return
fi

# Create temporary directory
ENVDIR="$(mktemp -d --suffix='-ipoolseq-env')"
trap "echo \"Removing $ENVDIR\"; rm -rf \"$ENVDIR\"; trap - RETURN" RETURN

echo "*** Creating $ENVDIR ..."
conda create -p "$ENVDIR" --no-default-packages --yes || return

echo "*** Activating $ENVDIR ..."
conda activate "$ENVDIR" || return

echo "*** Making $ENVDIR self-contained"
mkdir -p "$ENVDIR"/pkgs || return
conda config --env --add pkgs_dirs "$ENVDIR"/pkgs || return

echo "*** Enabling strict channel priority for $ENVDIR"
mkdir -p "$ENVDIR"/pkgs || return
conda config --env --set channel_priority strict || return

echo "*** Installing packages into $ENVDIR ..."
conda env update -f environment.yaml -p "$ENVDIR" --prune || return

echo "*** Packing environment ..."
cp environment.yaml "$ENVDIR" || return
rm -f environment.tar.gz.new
conda pack -p "$ENVDIR" -o environment.tar.gz.new --format tar.gz --compress-level 9 --n-threads 4 || return
mv environment.tar.gz.new environment.tar.gz || return

echo "*** Deactivating environment, returning to previously activate environment ..."
conda deactivate || return

echo "*** Updating environment.sha256"
sha256sum -b environment.tar.gz > environment.sha256 || return

echo "*** Comitting environment.tar.gz ..."
git add environment.tar.gz environment.sha256 || return
git commit -m "Updated environment.tar.gz based on environment.yaml rev. $(git log -n 1 --pretty=format:%h -- environment.yaml)" || return

echo "*** Comitting updated environent.rev ..."
git log -n 1 --pretty=format:%H -- environment.tar.gz > environment.rev || return
git add environment.rev || return
git commit -m "Updated environment.rev to $(git log -n 1 --pretty=format:%h -- environment.tar.gz) after updating environment.tar.gz based on environment.yaml rev. $(git log -n 1 --pretty=format:%h -- environment.yaml)" || return
