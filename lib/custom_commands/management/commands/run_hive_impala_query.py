#!/usr/bin/env python
import os
import logging
import datetime
import time
from pprint import pprint, pformat

from beeswax.server import dbms
from beeswax.conf import HIVE_SERVER_HOST
from django.contrib.auth.models import User

import desktop.conf

LOG = logging.getLogger(__name__)


class Command(BaseCommand):
  """
  Handler for renaming duplicate User objects
  """

  try:
    from optparse import make_option
    option_list = BaseCommand.option_list + (
      make_option("--hive", help=_t("Run Hive query."),
                  action="store_true", default=False, dest='runhive'),
      make_option("--impala", help=_t("Run Impala query."),
                  action="store_true", default=True, dest='runimpala'),
      make_option("--username", help=_t("User to run query as."),
                  action="store", default="admin", dest='username'),
      make_option("--query", help=_t("Query to run."),
                  action="store", default="select * from default.sample_07;", dest='query'),
    )

  except AttributeError, e:
    baseoption_test = 'BaseCommand' in str(e) and 'option_list' in str(e)
    if baseoption_test:
      def add_arguments(self, parser):
        parser.add_argument("--hive", help=_t("Run Hive query."),
                    action="store_true", default=False, dest='runhive'),
        parser.add_argument("--impala", help=_t("Run Impala query."),
                    action="store_true", default=True, dest='runimpala'),
        parser.add_argument("--username", help=_t("User to run query as."),
                    action="store", default="admin", dest='username'),
        parser.add_argument("--query", help=_t("Query to run."),
                    action="store", default="select * from default.sample_07;", dest='query')

    else:
      LOG.exception(str(e))
      sys.exit(1)


  def handle(self, *args, **options):
    LOG.warn("HUE_CONF_DIR: %s" % os.environ['HUE_CONF_DIR'])
    LOG.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
    LOG.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
    LOG.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
    LOG.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
    LOG.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))
    if options['runhive']:
      query_backend = 'hive'
    else:
      query_backend = 'impala'
      LOG.exception('Impala does not work yet')
      sys.exit(1)

    LOG.info("QUERY_BACKEND: %s" % query_backend)
    LOG.info("QUERY_USER: %s" % options['username'])
    LOG.info("QUERY: %s" % options['query'])
    LOG.info("QUERY_HOST: %s" % HIVE_SERVER_HOST)

    hue, created = User.objects.get_or_create(username=options['username'])

    start = time.time()
    db = dbms.get(hue)
    db.get_tables()

    executequery = query
    query = db.execute_statement(executequery)

    LOG.info(db.get_log(query.get_handle()))

    while True:
      ret = db.get_state(query.get_handle())
      LOG.info("ret: %s" % ret)
      LOG.info("ret.key: %s" % ret.key)
      if ret.key != 'running':
        break
      time.sleep(1)
      LOG.debug("Waiting for query execution")

    result = db.fetch(query.get_handle())

    i = 0
    for row in result.rows():
      LOG.debug("row: %s" % row)
      if i > 100:
        break
      i += 1

    LOG.debug(db.get_log(query.get_handle()))
    end = time.time()
    elapsed = (end - start) / 60
    LOG.debug("Time elapsed (minutes): %.2f" % elapsed)



