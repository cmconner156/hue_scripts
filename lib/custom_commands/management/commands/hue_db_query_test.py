#!/usr/bin/env python
import os
import sys
import time
import datetime
import re
import logging

from optparse import make_option

from django.core.management.base import BaseCommand, CommandError
from django.utils.translation import ugettext_lazy as _t, ugettext as _
from django.db.backends.oracle.base import Oracle_datetime
from django.db import connection

import desktop.conf

LOG = logging.getLogger(__name__)

class Command(BaseCommand):
  """
  Handler for running queries from Hue log with database_logging queries
  """

  option_list = BaseCommand.option_list + (
      make_option("--read-log-file", help=_t("Log file to scan for queries to be run "
                          "from database_logging = true."),
                          action="store_true",
                          default='/var/log/hue/runcpserver.log'),
      make_option("--start-time", help=_t("Start time to search for queries in log, format:"
                          '%d/%b/%Y %H:%M:%S IE: 01/Jan/2018 00:00:00: This is'
                          'standard Hue log format'),
                           action="store_true",
                           default=(datetime.datetime.now() - datetime.timedelta(minutes=2))),
      make_option("--end-time", help=_t("End time to search for queries in log, format:"
                          '%d/%b/%Y %H:%M:%S IE: 01/Jan/2018 00:00:00: This is'
                          'standard Hue log format'),
                           action="store_true",
                           default=(datetime.datetime.now())),
   )

  def handle(self, **options):
    LOG.warn("HUE_CONF_DIR: %s" % os.environ['HUE_CONF_DIR'])
    LOG.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
    LOG.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
    LOG.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
    LOG.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
    LOG.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))

    LOG.warn("Running database queries in file: %s: starting from: %s" % (options['read_log_file'], options['start_time']))

    start = time.time()

    oracleDatetimeRegex = re.compile(r"Oracle_datetime\([0-9,\ ]*\)")
    paramsFixRegex = re.compile(r",\ ")

    count = 1
    with open(options['read_log_file'], 'rU') as f:
      for line in f:
         if "QUERY" in line:
           junk, dateTemp = line.split('[')
           dateTemp = dateTemp.split(" ")
           log_time = datetime.datetime.strptime(dateTemp[0] + " " + dateTemp[1], "%d/%b/%Y %H:%M:%S")
           if options['start_time'] <= log_time <= options['end_time']:
             queryStart = time.time()
             line = oracleDatetimeRegex.sub("PLACEHOLDER", line)
             junk, query = line.split("QUERY = u'")
             query, param_base = query.split("' - PARAMS = (")
             params, junk = param_base.split(");")
    
             if params.endswith(','):
               params = params[:-1]

             params = paramsFixRegex.sub(",", params)
             params = params.split(',')

             for i in range(len(params)):
               updateArgsRegex = re.compile(r":arg%d" % i)
               if params[i] == "PLACEHOLDER":
                 query = updateArgsRegex.sub("'%s'" %Oracle_datetime.from_datetime(datetime.datetime.now()), query)
               else:
                 query = updateArgsRegex.sub(params[i], query)

             cursor = connection.cursor()
             cursor.execute(query)
             try:
               row = cursor.fetchone()
             except:
               LOG.warn("EXCEPTION: fetchone failed for query: %s" % query)

#              FETCH MANY MAY BE NEEDED
#              rows = cursor.fetchmany(GET_ITERATOR_CHUNK_SIZE)
#              while rows:
#                  rows = cursor.fetchmany(GET_ITERATOR_CHUNK_SIZE)

             count = count + 1
             queryEnd = time.time()
             queryElapsed = (queryEnd - queryStart)
             LOG.debug("Query time elapsed: %s: query: %s" % (queryElapsed, query))
             LOG.debug("")

    end = time.time()
    elapsed = (end - start) / 60
    LOG.debug("Total queries: %s: time elapsed (minutes): %.2f" % (count, elapsed))


