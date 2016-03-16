# Expand-Partition
Expand-Partition is a quick way to select a partition on a remote or local computer that is running Windows Server 2012+ to expand it to the max available size. This is a replacement to going into Disk Management or diskpart and choosing to extend a partition.

# Examples

Expand partition on the localhost
```
Expand-Partition
```

Expand partition on a remote host name or ip address
```
Expand-Partition -ComputerName remotehost
```
