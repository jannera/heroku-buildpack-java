#!/usr/bin/env bash
# bin/compile <build-dir> <cache-dir>

set -e            # fail fast
set -o pipefail   # don't ignore exit codes when piping output
# set -x          # enable debugging

# Configure directories
build_dir=$1
cache_dir=$2
env_dir=$3

bp_dir=$(cd $(dirname $0); cd ..; pwd)

# clean up leaking environment
unset GIT_DIR

# Load some convenience functions like status(), echo(), and indent()
source $bp_dir/bin/common.sh

source "$build_dir/_git.cfg"

if [ $GIT_VERSION ] && [ ! $git_version ]; then
  git_version=$GIT_VERSION
fi

# Recommend using semver ranges in a safe manner
if [ ! $git_version ]; then
  protip "You can specify a git version in _git.cfg"
  git_version=""
elif [ "$git_version" == "*" ]; then
  protip "Avoid using ranges like '*' in _git.cfg"
  git_version=""
elif [ ${git_version:0:1} == ">" ]; then
  protip "Avoid using ranges starting with '>' in _git.cfg"
  git_version=""
fi

# Output info about requested version and resolved git version
if [ "$git_version" == "" ]; then
  git_version="master"
  git_url="https://github.com/git/git/archive/master.tar.gz"
  status "Defaulting to latest master branch"
else
  git_url="https://github.com/git/git/archive/v$git_version.tar.gz"
  status "Requested git version: $git_version"
fi

git_src_dir="git-$git_version"

bin_dir=$build_dir/vendor/git

mkdir -p "$bin_dir"

if [ "$git_version" == "master" ] || ! test -d $cache_dir/git || ! test -f $cache_dir/git/.heroku/git-version || [ $(cat $cache_dir/git/.heroku/git-version) != "$git_version" ]; then
  status "Git version changed since last build; rebuilding dependencies"

  # Persist goodies like git-version in the slug
  mkdir -p $build_dir/.heroku

  # Save resolved git version in the slug for later reference
  echo $git_version > $build_dir/.heroku/git-version

  # Purge git-related cached content, being careful not to purge the top-level
  # cache, for the sake of heroku-buildpack-multi apps.
  status "Cleaning cached Git version..."
  rm -rf $cache_dir/git

  status "Downloading Git $git_version..."
  curl $git_url -sL -o - | tar xzf - -C $build_dir
  cd "$build_dir"
  cd $git_src_dir

  status "Compiling Git..."
  make NO_TCLTK=YesPlease NO_PERL=YesPlease NO_GETTEXT=YesPlease NO_SVN_TESTS=YesPlease NO_MSGFMT=YesPlease NO_MSGFMT_EXTENDED_OPTIONS=YesPlease CFLAGS="-Os -g0 -Wall" prefix="$bin_dir" install clean | indent
  status "Git was Installed at: $bin_dir"

  status "Cleaning up Git source files..."
  cd ..
  rm -rf $git_src_dir

  status "Caching Git binaries..."
  cp -R "$bin_dir" "$cache_dir"
  # Copy goodies to the cache
  cp -r $build_dir/.heroku $cache_dir/git

else
  status "Using cached Git $git_version..."
  cp -R "$cache_dir/git" "$build_dir/vendor"
fi

# Update the PATH
status "Building runtime environment"
mkdir -p $build_dir/.profile.d
echo "export PATH=\"\$HOME/vendor/git/bin:\$PATH\";" > $build_dir/.profile.d/git.sh