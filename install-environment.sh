#!/bin/bash

if [ -e "./environment" ] && ! [ -z "$(ls -A ./environment)" ]; then
	echo "./environment alreay exists and is non-emtpty. If you want to replace it, remove the old directory first!" >&2
	exit 1
fi

if [ ! -e "environment.tar.gz" ] || (head -n1 "environment.tar.gz" | grep '^version ' > /dev/null); then
	# Looks like environment.tar.gz is a git LFS pointer, not the real file.
	# Directly downloading the file given its pointer would require git-lfs to
	# be installed, so instead we rely to environment.ref to point to a revision
	# containing the correct file, and download that revision directly from GitHub.
	# Luckily, when directly downloading a file, GitHub will handle LFS blobs
	# correctly, and redirect us to the actual storage site.
	echo "*** environment.tar.gz is only a git LFS pointer, downloading original from GitHub"
	URL="http://github.com/Cibiv/ipoolseq-pipeline/raw/$(cat environment.rev)/environment.tar.gz"
	while true; do
		if [ -x "$(command -v curl)" ]; then
			curl -O -L "$URL" || exit 1
		elif [ -x "$(command -v wget)" ]; then
			wget "$URL" || exit 1
		else
			echo "Neither curl nor wget are installed, one of these is required to download the environment" >&2
			exit 1
		fi

		if [ -x "$(command -v sha256sum)" ]; then
			echo "*** Verifying the integrity of environment.tar.gz"
			if ! sha256sum -c environment.sha256; then
				echo "*** Downloaded environment.tar.gz is corrupt, will remove and retry"
				rm environment.tar.gz
				continue
			fi
		else
			echo "*** sha256sum is not available, cannot verify environment.tar.gz, trusting that the download was OK"
		fi
		break
	done
else
	if [ -x "$(command -v sha256sum)" ]; then
		echo "*** Verifying the integrity of environment.tar.gz"
		sha256sum -c environment.sha256 || exit 1
	else
		echo "*** sha256sum is not available, cannot verify environment.tar.gz"
	fi
fi


echo "*** Unpacking environment.tar.gz"
test -e ./environment || mkdir ./environment || exit 1
tar -xzf environment.tar.gz -C environment || exit 1

echo "*** Cleanup prefixes in ./environment"
source ./environment/bin/activate
conda-unpack || exit 1

echo "*** DONE"
echo "The environment is now usable and can be activated with"
echo ""
echo "  source ./environment/bin/activate"
echo ""
echo "The environment must be re-activated in every terminal session"
