import os
import sys
import logging
import datetime
import time
import subprocess

from cm_environment import check_security
from hue_shared import which

LOG = logging.getLogger(__name__)

class Curl(object):

  def __init__(self):
    self.curl = which('curl')
    if self.curl is None:
      LOG.exception("curl is required, please install and rerun")
      sys.exit(1)

    self.security_enabled = check_security()

  def do_curl(self, method='GET', url=None):

    LOG.info("curl: %s" % self.curl)


