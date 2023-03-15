[
  {
    Datatype: 'lshw',
    Filename: 'lshw.json',
    Cmd: ['lshw', '-json'],
  },
  {
    Datatype: 'lspci',
    Filename: 'lspci.txt',
    Cmd: ['lspci', '-mm', '-vv', '-k', '-nn'],
  },
  {
    Datatype: 'lsusb',
    Filename: 'lsusb.txt',
    Cmd: ['lsusb', '-v'],
  },
  {
    Datatype: 'ipaddress',
    Filename: 'ip-address.txt',
    Cmd: ['ip', 'address', 'show'],
  },
  {
    Datatype: 'iproute4',
    Filename: 'ip-route-4.txt',
    Cmd: ['ip', '-4', 'route', 'show'],
  },
  {
    Datatype: 'iproute6',
    Filename: 'ip-route-6.txt',
    Cmd: ['ip', '-6', 'route', 'show'],
  },
  {
    Datatype: 'uname',
    Filename: 'uname.txt',
    Cmd: ['uname', '-a'],
  },
  {
    Datatype: 'osrelease',
    Filename: 'os-release.txt',
    Cmd: ['cat', '/etc/os-release'],
  },
  {
    Datatype: 'biosversion',
    Filename: 'bios_version.txt',
    Cmd: ['cat', '/sys/class/dmi/id/bios_version'],
  },
  {
    Datatype: 'chassisserial',
    Filename: 'chassis_serial.txt',
    Cmd: ['cat', '/sys/class/dmi/id/chassis_serial'],
  },
]
