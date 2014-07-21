# Copyright (c) 2012 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

test_image_content() {
  local root="$1"
  local returncode=0

  if [[ -z "$BOARD" ]]; then
    die '$BOARD is undefined!'
  fi
  local portageq="portageq-$BOARD"

  local binaries=(
    "$root/usr/boot/vmlinuz"
    "$root/bin/sed"
  )

  for test_file in "${binaries[@]}"; do
    if [ ! -f "$test_file" ]; then
      error "test_image_content: Cannot find '$test_file'"
      returncode=1
    fi
  done

  local libs=( $(sudo find "$root" -type f -name '*.so*') )

  # Check that all .so files, plus the binaries, have the appropriate
  # dependencies.
  local check_deps="${BUILD_LIBRARY_DIR}/check_deps"
  if ! "$check_deps"  "$root" "${binaries[@]}" "${libs[@]}"; then
    error "test_image_content: Failed dependency check"
    returncode=1
  fi

  local blacklist_dirs=(
    "$root/usr/share/locale"
  )
  for dir in "${blacklist_dirs[@]}"; do
    if [ -d "$dir" ]; then
      warn "test_image_content: Blacklisted directory found: $dir"
      # Only a warning for now, size isn't important enough to kill time
      # playing whack-a-mole on things like this this yet.
      #error "test_image_content: Blacklisted directory found: $dir"
      #returncode=1
    fi
  done

  # Check that there are no conflicts between /* and /usr/*
  local pkgdb=$(ROOT="${root}" $portageq vdb_path)
  local files=$(awk '$2 ~ /^\/(bin|sbin|lib|lib32|lib64)\// {print $2}' \
                "${pkgdb}"/*/*/CONTENTS)
  local check_file
  for check_file in $files; do
    if grep -q "^... /usr$check_file " "${pkgdb}"/*/*/CONTENTS; then
      error "test_image_content: $check_file conflicts with /usr$check_file"
      returncode=1
    fi
  done

  # Check for bug https://bugs.gentoo.org/show_bug.cgi?id=490014
  if lbzcat "${pkgdb}"/*/*/environment.bz2 | grep '^declare -. EROOT='; then
    error "test_image_content: EROOT preserved in ebuild environment"
    returncode=1
  fi

  return $returncode
}
