[
  {
    Name: 'lshw',
    Cmd: ['lshw'],
  },
  {
    Name: 'lspci',
    Cmd: ['lspci', '-mm', '-vv', '-k', '-nn'],
  },
  {
    Name: 'lsusb',
    Cmd: ['lsusb', '-v'],
  },
  {
    Name: 'ipaddress',
    Cmd: ['ip', 'address', 'show'],
  },
  {
    Name: 'iproute4',
    Cmd: ['ip', '-4', 'route', 'show'],
  },
  {
    Name: 'iproute6',
    Cmd: ['ip', '-6', 'route', 'show'],
  },
  {
    Name: 'uname',
    Cmd: ['uname', '-a'],
  },
  {
    Name: 'osrelease',
    Cmd: ['cat', '/etc/os-release'],
  },
]
