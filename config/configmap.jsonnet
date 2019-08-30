{
  metadata(name, contents):: {
      name: name + '-' + std.md5(std.toString(contents)),
      annotations+: {
          'mlab/deploymentstamp': std.extVar('DEPLOYMENTSTAMP'),
          'mlab/configmaptruename': name,
      },
  },
}
