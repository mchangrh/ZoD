# ZFS on DVD/ Disk Image

Based on a [Medium post](https://medium.com/@cryptographrix/zfs-on-dvds-as-an-insane-backup-method-9e722d30e949) by [@cryptographrix](https://github.com/cryptographrix)

Semi-automated ZFS on DVD/ Disk Image creation, mounting and management.

```
Usage: zod.sh [command] [options]
Commands:
  create                 Create a new disk image pool
  export                 Export a disk image pool
  mount                  Mount a disk image pool
Options:
  -n, --name <name>      Pool name
  -f, --folder <path>    Image path (default: current directory)
  -h, --help             Display this help and exit
Options (create):
  -d, --data <count>     Number of data disks (default: 2)
  -p, --parity <count>   Number of parity disks (default: 0)
  -s, --size <size>      Size of pool in MiB
```
