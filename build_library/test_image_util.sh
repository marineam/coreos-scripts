# Copyright (c) 2011 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Shell function library for functions specific to creating test
# images from dev images.  This file also contains additional
# functions and initialization shared between build_image and
# mod_image_for_test.sh.
#
# TODO(jrbarnette): The two halves of this file aren't particularly
# related; they're together merely to consolidate the shared code in
# one file.  Arguably, they should be broken up.


# ----
# The initialization and functions below are shared between
# build_image and mod_image_for_test.sh.  The code is not used
# by the mod_image_for_test function.

EMERGE_BOARD_CMD="emerge-$BOARD"
if [ $FLAGS_fast -eq $FLAGS_TRUE ]; then
  echo "Using alternate emerge"
  EMERGE_BOARD_CMD="$GCLIENT_ROOT/chromite/bin/parallel_emerge"
  EMERGE_BOARD_CMD="$EMERGE_BOARD_CMD --board=$BOARD"
fi
if [ $FLAGS_jobs -ne -1 ]; then
  EMERGE_JOBS="--jobs=$FLAGS_jobs"
fi

export INSTALL_MASK="${DEFAULT_INSTALL_MASK}"


# Utility function for creating a copy of an image prior to
# modification:
#  $1: source image path
#  $2: destination image path
copy_image() {
  local src_base=$(basename "$1")
  local dst_base=$(basename "$2")
  echo "Creating $dst_base from $src_base..."
  $COMMON_PV_CAT "$1" >"$2" ||
    die "Cannot copy $src_base to $dst_base"
}

# Basic command to emerge binary packages into the target image.
# Arguments to this command are passed as addition options/arguments
# to the basic emerge command.
emerge_to_image() {
  sudo -E ${EMERGE_BOARD_CMD} --root-deps=rdeps --usepkgonly -v \
    "$@" ${EMERGE_JOBS}
}

# ----
# From here down, the main exported function is
# 'mod_image_for_test'.  The remainder of the code is not used
# outside this file.

# Emerges chromeos-test onto the image.
emerge_chromeos_test() {
  # Determine the root dir for test packages.
  local root_dev_dir="${ROOT_FS_DIR}/usr/local"

  emerge_to_image --root="${root_dev_dir}" chromeos-test
}

prepare_hwid_for_factory() {
  local hwid_dest="$1/hwid"
  local hwid_src="${BOARD_ROOT}/usr/share/chromeos-hwid"

  # Force refreshing source folder in build root folder
  sudo rm -rf "${hwid_src}" "${hwid_dest}"
  emerge_to_image chromeos-hwid
  if [ -d "${hwid_src}" ]; then
    # TODO(hungte) After being archived by chromite, the HWID files will be in
    # factory_test/hwid; we should move it to top level folder.
    cp -r "${hwid_src}" "${hwid_dest}"
  else
    echo "Skipping HWID: No HWID bundles found."
  fi
}

install_autotest_for_factory() {
  local autotest_src="${BOARD_ROOT}/usr/local/autotest"
  local stateful_root="${ROOT_FS_DIR}/usr/local"
  local autotest_client="${stateful_root}/autotest"

  echo "Install autotest into stateful partition from ${autotest_src}"

  sudo mkdir -p "${autotest_client}"

  # Remove excess files from stateful partition.
  sudo rm -rf "${autotest_client}/"*
  sudo rm -rf "${stateful_root}/autotest-pkgs"
  sudo rm -rf "${stateful_root}/lib/icedtea6"

  sudo rsync --delete --delete-excluded -au \
    --exclude=deps/realtimecomm_playground \
    --exclude=tests/ltp \
    --exclude=site_tests/graphics_O3DSelenium \
    --exclude=site_tests/realtimecomm_GTalk\* \
    --exclude=site_tests/platform_StackProtector \
    --exclude=deps/chrome_test \
    --exclude=site_tests/desktopui_BrowserTest \
    --exclude=site_tests/desktopui_PageCyclerTests \
    --exclude=site_tests/desktopui_UITest \
    --exclude=.svn \
    "${autotest_src}/client/"* "${autotest_client}"

  sudo chmod 755 "${autotest_client}"
  sudo chown -R 1000:1000 "${autotest_client}"
}

# convert a dev image into a test or factory test image
mod_image_for_test () {
  local test_pathname="$1"

  local image_dir=$(dirname ${test_pathname})
  local image_name=$(basename ${test_pathname})

  trap unmount_image EXIT
  mount_image "${image_dir}/${image_name}" \
    "${ROOT_FS_DIR}" "${STATEFUL_FS_DIR}"

  emerge_chromeos_test

  BACKDOOR=0
  if [ $FLAGS_standard_backdoor -eq $FLAGS_TRUE ]; then
    BACKDOOR=1
  fi

  local mod_test_script="${SCRIPTS_DIR}/mod_for_test_scripts/test_setup.sh"
  # Run test setup script to modify the image
  sudo -E GCLIENT_ROOT="${GCLIENT_ROOT}" ROOT_FS_DIR="${ROOT_FS_DIR}" \
    STATEFUL_DIR="${STATEFUL_FS_DIR}" ARCH="${ARCH}" BACKDOOR="${BACKDOOR}" \
    "${mod_test_script}"

  if [ ${FLAGS_factory} -eq ${FLAGS_TRUE} ]; then
    emerge_to_image --root="${ROOT_FS_DIR}" factorytest-init

    prepare_hwid_for_factory "${image_dir}"
    install_autotest_for_factory

    local mod_factory_script
    mod_factory_script="${SCRIPTS_DIR}/mod_for_factory_scripts/factory_setup.sh"
    # Run factory setup script to modify the image
    sudo -E GCLIENT_ROOT="${GCLIENT_ROOT}" ROOT_FS_DIR="${ROOT_FS_DIR}" \
            BOARD="${BOARD}" "${mod_factory_script}"
  fi

  # Re-run ldconfig to fix /etc/ldconfig.so.cache.
  sudo ldconfig -r "${ROOT_FS_DIR}"

  unmount_image
  trap - EXIT

  # Now make it bootable with the flags from build_image
  "${SCRIPTS_DIR}/bin/cros_make_image_bootable" "${image_dir}" \
                                                "${image_name}" \
                                                --force_developer_mode
}
