#!/usr/bin/env python
import os
import sys
import logging
import datetime
import time
import subprocess

from django.core.management.base import BaseCommand, CommandError
from django.utils.translation import ugettext_lazy as _t, ugettext as _

import desktop.conf

LOG = logging.getLogger(__name__)
security_enabled = False

def which(file_name):
  for path in os.environ["PATH"].split(os.pathsep):
    full_path = os.path.join(path, file_name)
    if os.path.exists(full_path) and os.access(full_path, os.X_OK):
      return full_path
  return None

from hadoop import conf
hdfs_config = conf.HDFS_CLUSTERS['default']
if hdfs_config.SECURITY_ENABLED.get():
  LOG.info("%s" % desktop.conf.KERBEROS.CCACHE_PATH.get())
  os.environ['KRB5CCNAME'] = desktop.conf.KERBEROS.CCACHE_PATH.get()
  KLIST = which('klist')
  if KLIST is None:
    LOG.exception("klist is required, please install and rerun")
    sys.exit(1)
  klist_cmd = '%s | grep "Default principal"' % KLIST
  LOG.info("KLIST: %s" % klist_cmd)
  klist_check = subprocess.Popen(klist_cmd, shell=False, stdout=subprocess.PIPE)
  klist_princ = klist_check.communicate()
  LOG.info("klist_princ: %s" % klist_princ)
#  klist_princ = klist_check.communicate()[0].split('\n')[0]
  security_enabled = True

CURL = which('curl')

def do_curl(method='GET', url=None, security_enabled=False):
  LOG.info("CURL: %s" % CURL)

class Command(BaseCommand):
  """
  Handler for renaming duplicate User objects
  """

  try:
    from optparse import make_option
    option_list = BaseCommand.option_list + (
      make_option("--service", help=_t("Service to test, all, httpfs, solr, oozie, rm, jhs, sparkhs."),
                  action="store", default='all', dest='service'),
      make_option("--showcurl", help=_t("Show curl commands."),
                  action="store_true", default=False, dest='showcurl'),
      make_option("--response", help=_t("Show entire REST response."),
                  action="store_true", default=False, dest='entireresponse'),
      make_option("--username", help=_t("User to doAs."),
                  action="store", default="admin", dest='username'),
    )

  except AttributeError, e:
    baseoption_test = 'BaseCommand' in str(e) and 'option_list' in str(e)
    if baseoption_test:
      def add_arguments(self, parser):
        parser.add_argument("--service", help=_t("Service to test, all, httpfs, solr, oozie, rm, jhs, sparkhs."),
                    action="store", default='all', dest='service'),
        parser.add_argument("--showcurl", help=_t("Show curl commands."),
                    action="store_true", default=False, dest='showcurl'),
        parser.add_argument("--response", help=_t("Show entire REST response."),
                    action="store_true", default=False, dest='entireresponse'),
        parser.add_argument("--username", help=_t("User to doAs."),
                    action="store", default="admin", dest='username')
    else:
      LOG.exception(str(e))
      sys.exit(1)

  def handle(self, *args, **options):

    if CURL is None:
      LOG.exception("curl is required, please install and rerun")
      sys.exit(1)

    available_services = {}

    if options['service'] == "all" or options['service'] == "solr":
      from search.conf import SOLR_URL, SECURITY_ENABLED
      if hasattr(SOLR_URL, 'get'):
        available_services['solr'] = {}
        available_services['solr']['url'] = SOLR_URL.get()
        available_services['solr']['tests'] = {}
        available_services['solr']['tests']['jmx'] = {}
        available_services['solr']['tests']['jmx']['url'] = '/jmx'
        available_services['solr']['tests']['jmx']['method'] = 'GET'
        available_services['solr']['tests']['jmx']['test'] = 'solr.solrxml.location'
        if hasattr(SECURITY_ENABLED, 'get'):
          available_services['solr']['security_enabled'] = SECURITY_ENABLED.get()
        else:
          available_services['solr']['security_enabled'] = False
      else:
        LOG.info("Hue does not have Solr configured, cannot test Solr")

    LOG.info("security_enabled: %s" % security_enabled)
    do_curl()


