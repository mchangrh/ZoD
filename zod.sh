#!/usr/bin/env bash

set -eo pipefail

HELPTEXT="Usage: zod.sh [command] [options]
Commands:
  create                 Create a new disk image pool
  export                 Export a disk image pool
  mount                  Mount a disk image pool
Options:
  -n, --name <name>      Pool name
  -f, --folder <path>    Folder path (default: current directory)
  -h, --help             Display this help and exit
Options (create):
  -d, --data <count>     Number of data disks (default: 2)
  -p, --parity <count>   Number of parity disks (default: 0)
  -s, --size <size>      Size of pool in MiB"

if [[ $# -eq 0 ]]; then
  echo "$HELPTEXT"
  exit 1
fi

# check for command
case $1 in
  create)
    shift
    ;;
  export)
    shift
    ;;
  mount)
    shift
    ;;
  *)
    echo "Unknown command $1"
    echo "$HELPTEXT"
    exit 1
    ;;
esac

# argument parsing
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      echo "$HELPTEXT"
      exit 1
      ;;
    -n|--name)
      POOL_NAME="$2"
      shift # past argument
      shift # past value
      ;;
    -d|--data)
      DATA_DISKS="$2"
      shift # past argument
      shift # past value
      ;;
    -p|--parity)
      PARITY_DISKS="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--size)
      SIZE="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output)
      OUTPUT_PATH="$2"
      shift # past argument
      shift # past value
      ;;
    -*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      shift # past argument
      ;;
  esac
done

POOLDIR="$OUTPUT_PATH/$POOL_NAME"

# validate generic arguments
function validate() {
  if [[ -z $POOL_NAME ]]; then
    echo "-n | --name Pool name is required"
    exit 1
  elif [[ -z $OUTPUT_PATH ]]; then
    OUTPUT_PATH="$PWD"
  fi
}

function validate_create_args() {
  if [[ -z $SIZE ]]; then
    echo "-s | --size Size is required"
    exit 1
  fi
  # validate parity disks 0 <= x <= 3
  if [[ -n $PARITY_DISKS ]]; then
    if [[ $PARITY_DISKS -lt 0 || $PARITY_DISKS -gt 3 ]]; then
      echo "Parity disks must be between 0 and 3"
      exit 1
    fi
  else
    PARITY_DISKS=0
  fi
  # validate disks
  if [[ -n $DATA_DISKS ]]; then
    if [[ $DATA_DISKS -lt 1 ]]; then
      echo "Data disks must be greater than 1"
      exit 1
    fi
  else
    DATA_DISKS=2
  fi
}

function validate_create_logic() {
  # confirm mirror > 3
  if [[ $RAIDZ_TYPE == "mirror" && $DATA_DISKS -gt 3 ]]; then
    echo "Please confirm that you want to use a mirror with more than 3 disks"
    read -p "Do you want to continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Aborting"
      exit 1
    fi
  fi
}

function create_img_setup {
  # create images
  mkdir -p "$POOLDIR"
  SPACER_IMG="$POOLDIR/.spacer.img"
  fallocate -l "$SIZE"MB "$SPACER_IMG" ||
    echo "Switching to dd" &&
      dd if=/dev/zero of="$SPACER_IMG" bs=1M count="$SIZE" status=none
  # shellcheck disable=SC2086
  mkdir -p "$POOLDIR"/mnt
  # create image, mountpoints and mount
  # shellcheck disable=SC2086
  for i in $(seq 1 $DISK_COUNT); do
    # set up disk img
    DISK_IMG="$POOLDIR/disk-$i.img"
    cp "$POOLDIR/.spacer.img" "$DISK_IMG"
    losetup -f "$DISK_IMG"
    # mount point
    MOUNT_POINT="$POOLDIR/mnt/disk-$i"
    touch "$MOUNT_POINT"
    mount -t none -o bind "$(losetup -j "$DISK_IMG" -lnO name)" "$MOUNT_POINT"
  done
}

function create() {
  validate
  validate_create_args
  # set up variables
  DISK_COUNT=$((DATA_DISKS + PARITY_DISKS))
  # figure out raidz type
  if [[ $PARITY_DISKS -eq 0 ]]; then
    RAIDZ_TYPE="mirror"
  elif [[ $PARITY_DISKS -gt 0 ]]; then
    RAIDZ_TYPE="raidz${PARITY_DISKS}"
  fi
  # calculate size
  if [[ -n $SIZE ]]; then
    if [[ $RAIDZ_TYPE == "mirror" ]]; then
      IMG_SIZE=$SIZE
    else
      IMG_SIZE=$((SIZE / DATA_DISKS))
    fi
  fi
  # ask for confirmation
  echo "Creating pool \`$POOL_NAME\`"
  echo "Using $RAIDZ_TYPE with $DATA_DISKS data disks and $PARITY_DISKS parity disks"
  echo "Data will be across $DISK_COUNT x $IMG_SIZE MiB disk images"
  echo "Total usable size of $SIZE MiB"
  echo "Images will be created in $OUTPUT_PATH/$POOL_NAME"
  read -p "Do you want to continue? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting"
    exit 1
  fi
  # create images
  create_img_setup
  zpool create -f "$POOL_NAME" "$RAIDZ_TYPE" "$POOLDIR"/mnt/disk-*
  # show zpool status
  echo "zpool created successfully"
  zpool status "$POOL_NAME"

  # remove base image
  rm "$POOLDIR"/.spacer.img
}

function export() {
  validate
  # export pool
  zpool export "$POOL_NAME"
  echo "zpool exported successfully"
  # unmount images
  for imagename in "$POOLDIR"/*.img; do
    MOUNT_POINT="$POOLDIR/mnt/disk-$i"
    umount "$MOUNT_POINT"
    losetup -d "$(losetup -j "$imagename" -lnO name)"
  done
  echo "Images unmounted successfully"
}

function mount() {
  validate
  # mount images
  mkdir -p "$POOLDIR"/mnt
  for imagename in "$POOLDIR"/*.img; do
    MOUNT_POINT="$POOLDIR/mnt/disk-$i"
    touch "$MOUNT_POINT"
    mount -t none -o bind "$(losetup -j "$imagename" -lnO name)" "$MOUNT_POINT"
  done
  # mount pool
  zpool import -d "$POOLDIR/mnt/disk-*" "$POOL_NAME"
  echo "zpool mounted successfully"
  zpool status "$POOL_NAME"
}