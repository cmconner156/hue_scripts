#!/usr/bin/env python2.6

import os; activate_this=os.path.join(os.path.dirname(os.path.realpath('/opt/cloudera/parcels/CDH/lib/hue/build/env/bin/activate_this.py')), 'activate_this.py'); exec(compile(open(activate_this).read(), activate_this, 'exec'), dict(__file__=activate_this)); del activate_this
#import os; activate_this=os.path.join(os.path.dirname(os.path.realpath('/usr/lib64/cmf/agent/build/env/bin/activate_this.py')), 'activate_this.py'); execfile(activate_this, dict(__file__=activate_this)); del activate_this

import sys

script_dir = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, script_dir + '/lib')

import logging
import logging.handlers
import json
import argparse
import re
import time

import requests
from requests_kerberos import HTTPKerberosAuth, REQUIRED, OPTIONAL
import httplib as http_client

parser = argparse.ArgumentParser()

parser.add_argument('-u', action='store', dest='url', default='http://localhost:14000',
                    help='HTTPFS base URL IE: https://httpfs.example.com:14000')

parser.add_argument('-U', action='store', dest='user', default='hdfs',
                    help='User to impersonate')

parser.add_argument('-v', action='store', dest='validate', default=False,
                    help='Validate certificate')

args = parser.parse_args()

http_client.HTTPConnection.debuglevel = 1

LOGFILE = "/var/log/hue/hue_hdfs_test.log"
logrotatesize=10
backupcount=10
LOG = logging.getLogger()
format = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fh = logging.handlers.RotatingFileHandler(LOGFILE, maxBytes = (1048576*logrotatesize), backupCount = backupcount)
fh.setFormatter(format)
LOG.addHandler(fh)
LOG.setLevel(logging.DEBUG)

requests_log = logging.getLogger("requests.packages.urllib3")
requests_log.addHandler(fh)
requests_log.setLevel(logging.DEBUG)
requests_log.propagate = True

kerberos_auth = HTTPKerberosAuth(mutual_authentication=OPTIONAL)

sess = requests.Session()

method = "get"
params = {'op':'GETFILESTATUS','user.name':'hue','doAs':args.user}
while True:
  resp = sess.get("%s/webhdfs/v1/tmp" % args.url, verify=args.validate, params=params, auth=kerberos_auth, allow_redirects=True)
  LOG.info("%s Got response: %s%s" %
          (method,
           resp.content[:1000],
           len(resp.content) > 1000 and "..." or ""))
  sess.close()
  time.sleep(60)


