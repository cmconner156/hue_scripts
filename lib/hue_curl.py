import os
import sys
import logging
import datetime
import time
import subprocess

from cm_environment import check_security
from hue_shared import which

#logging.basicConfig()
#logging = logging.getLogger(__name__)

class Curl(object):

  def __init__(self):
    self.curl = which('curl')
    if self.curl is None:
      logging.exception("curl is required, please install and rerun")
      sys.exit(1)

    logging.info("Checking security status")
    self.security_enabled = check_security()

  def do_curl(self, method='GET', url=None):

    logging.info("security_enabled: %s" % self.security_enabled)
    logging.info("curl: %s" % self.curl)


