#!/usr/bin/env python
"""Serves up the certs a client needs.

Will only serve up certs to clients with IP addresses in the whitelist. This
server must be run by a user that is also allowed to run the kubeadm command.

This code is bad and pboothe@google.com should (and does!) feel bad for writing
it. The only balm is the fact that it replaces a system which posted these
tokens in a public location. This system needs to be rewritten, in go, with
https and with interaction with the ePoxy server. It has no tests, because such
tests would be an indication of quality, which is not present here.

Pacem
https://hyperallergic.com/312318/a-nuclear-warning-designed-to-last-10000-years/
  This place is not a place of honor.
  No highly esteemed deed is commemorated here.
  Nothing valued is here.
"""

import BaseHTTPServer
import json
import subprocess
import sys
import textwrap

import httplib2

KUBEADM_BINARY = '/usr/bin/kubeadm'


def get_whitelist():
    """Retrieves the IP whitelist from GCS and returns the set of valid IPs."""
    http = httplib2.Http()
    url = ('https://storage.googleapis.com/operator-mlab-sandbox/'
           'metadata/v0/current/mlab-host-ips.json')
    resp, content = http.request(url)
    assert resp.status == 200
    jsondata = json.loads(content)
    return set(entry['ipv4'] for entry in jsondata)


class K8sTokenRequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    """The request handler for our terrible microservice."""

    def do_GET(self):
        """Respond to a GET request.

        - If the remote end is not on the IP whitelist,return 403.
        - Otherwise, if everything works, return 200 and some JSON.
        - If everything doesn't work, return 500 and the error.
        """
        host, _ = self.client_address
        if host not in get_whitelist():
            self.send_error(403)
            return
        try:
            token = subprocess.check_output([
                KUBEADM_BINARY, 'token', 'create', '--ttl', '5m',
                '--description',
                'Token to allow %s to join the cluster' % self.address_string()
            ])
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(
                textwrap.dedent("""\
                                {
                                    "token": "%s"
                                }
                                """ % token.strip()))
            return
        except subprocess.CalledProcessError as cpe:
            self.send_error(500,
                            'The server had something go wrong: %s' % str(cpe))
            return


def main(_argv):
    """Serve up the microservice on port 8000."""
    server_address = ('', 8000)
    httpd = BaseHTTPServer.HTTPServer(server_address, K8sTokenRequestHandler)
    httpd.serve_forever()


if __name__ == '__main__':
    main(sys.argv)
