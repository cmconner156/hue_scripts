#!/usr/bin/env python
import os
import sys
import logging
import datetime
import time

from django.core.management.base import BaseCommand, CommandError
from django.utils.translation import ugettext_lazy as _t, ugettext as _

import desktop.conf

from hue_curl import Curl

#logging.basicConfig()
#logging = logging.getLogger(__name__)


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
      logging.exception(str(e))
      sys.exit(1)

  def handle(self, *args, **options):

    curl = Curl()

    available_services = {}

    if options['service'] == "all" or options['service'] == "solr":
      from search.conf import SOLR_URL, SECURITY_ENABLED
      if hasattr(SOLR_URL, 'get'):
        available_services['solr'] = {}
        available_services['solr']['url'] = SOLR_URL.get()
        available_services['solr']['tests'] = {}
        available_services['solr']['tests']['jmx'] = {}
        available_services['solr']['tests']['jmx']['url'] = '%s/jmx' % available_services['solr']['url']
        available_services['solr']['tests']['jmx']['method'] = 'GET'
        available_services['solr']['tests']['jmx']['test'] = 'solr.solrxml.location'
        if hasattr(SECURITY_ENABLED, 'get'):
          available_services['solr']['security_enabled'] = SECURITY_ENABLED.get()
        else:
          available_services['solr']['security_enabled'] = False
      else:
        logging.info("Hue does not have Solr configured, cannot test Solr")

    logging.info("Running Solr JMX Test:")
    response = curl.do_curl_available_services(available_services['solr']['tests']['jmx'])
    if options['entireresponse']:
      logging.info("Solr JMX Test Response: %s" % response)
    else:
      if available_services['solr']['tests']['jmx']['test'] in response:
        logging.info("Solr JMX Test Passed: %s found in response" % available_services['solr']['tests']['jmx']['test'])


