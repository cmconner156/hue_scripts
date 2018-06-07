#!/usr/bin/env python
import os
import time

from optparse import make_option

from django.core.management.base import BaseCommand, CommandError
from django.utils.translation import ugettext_lazy as _t, ugettext as _
from beeswax.models import SavedQuery
from beeswax.models import Session
from datetime import date, timedelta
from oozie.models import Workflow
from django.db.utils import DatabaseError
import desktop.conf
from desktop.models import Document2
import logging
import logging.handlers


import desktop.conf

LOG = logging.getLogger(__name__)


class Command(BaseCommand):
    """
    Handler for purging old Query History, Workflow documents and Session data
    """

    option_list = BaseCommand.option_list + (
        make_option("--keep-days", help=_t("Number of days of history data to keep."),
                    action="store",
                    type=int,
                    default=30),
    )

    def handle(self, *args, **options):
        LOG.warn("HUE_CONF_DIR: %s" % os.environ['HUE_CONF_DIR'])
        LOG.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
        LOG.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
        LOG.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
        LOG.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
        LOG.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))
        LOG.info("Cleaning up anything in the Hue tables oozie*, desktop* and beeswax* older than %s old" % options['keep_days'])

        resetCount = 15
        resetMax = 5
        errorCount = 0
        checkCount = 0
        resets = 0
        deleteRecordsBase = 999  #number of documents to delete in a batch
                                      #to avoid Non Fatal Exception: DatabaseError: too many SQL variables
        deleteRecords = deleteRecordsBase
        start = time.time()

        #Clean out Hive / Impala Query History
        totalQuerys = SavedQuery.objects.filter(is_auto=True, mtime__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)
        LOG.info("Looping through querys. %s querys to be deleted." % totalQuerys.count())
        while totalQuerys.count():
          if deleteRecords < 30 and resets < resetMax:
            checkCount += 1
          if checkCount == resetCount:
            deleteRecords = deleteRecordsBase
            resets += 1
            checkCount = 0
          LOG.info("SavedQuerys left: %s" % totalQuerys.count())
          savedQuerys = SavedQuery.objects.filter(is_auto=True, mtime__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)[:deleteRecords]
          try:
            SavedQuery.objects.filter(pk__in = list(savedQuerys)).delete()
            errorCount = 0
          except DatabaseError, e:
            LOG.info("Non Fatal Exception: %s: %s" % (e.__class__.__name__, e))
            errorCount += 1
            if errorCount > 9 and deleteRecords == 1:
              raise
            if deleteRecords > 100:
              deleteRecords = max(deleteRecords - 100, 1)
            else:
              deleteRecords = max(deleteRecords - 10, 1)
            LOG.info("Decreasing max delete records for SavedQuerys to: %s" % deleteRecords)
          totalQuerys = SavedQuery.objects.filter(is_auto=True, mtime__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)

        errorCount = 0
        checkCount = 0
        resets = 0
        deleteRecords = deleteRecordsBase

        totalWorkflows = Workflow.objects.filter(is_trashed=True, last_modified__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)
        LOG.info("Looping through trashed workflows. %s workflows to be deleted." % totalWorkflows.count())
        while totalWorkflows.count():
          if deleteRecords < 30 and resets < resetMax:
            checkCount += 1
          if checkCount == resetCount:
            deleteRecords = deleteRecordsBase
            resets += 1
            checkCount = 0
          LOG.info("Workflows left: %s" % totalWorkflows.count())
          deleteWorkflows = Workflow.objects.filter(is_trashed=True, last_modified__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)[:deleteRecords]
          try:
            Workflow.objects.filter(pk__in = list(deleteWorkflows)).delete()
            errorCount = 0
          except DatabaseError, e:
            log.info("Non Fatal Exception: %s: %s" % (e.__class__.__name__, e))
            errorCount += 1
            if errorCount > 9 and deleteRecords == 1:
              raise
            if deleteRecords > 100:
              deleteRecords = max(deleteRecords - 100, 1)
            else:
              deleteRecords = max(deleteRecords - 10, 1)
            LOG.info("Decreasing max delete records for Workflows to: %s" % deleteRecords)
          totalWorkflows = Workflow.objects.filter(is_trashed=True, last_modified__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)

        errorCount = 0
        checkCount = 0
        resets = 0
        deleteRecords = deleteRecordsBase

        totalWorkflows = Workflow.objects.filter(name='', last_modified__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)
        LOG.info("Looping through duplicate workflows. %s workflows to be deleted." % totalWorkflows.count())
        while totalWorkflows.count():
          if deleteRecords < 30 and resets < resetMax:
            checkCount += 1
          if checkCount == resetCount:
            deleteRecords = deleteRecordsBase
            resets += 1
            checkCount = 0
          LOG.info("Workflows left: %s" % totalWorkflows.count())
          deleteWorkflows = Workflow.objects.filter(name='', last_modified__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)[:deleteRecords]
          try:
            Workflow.objects.filter(pk__in = list(deleteWorkflows)).delete()
            errorCount = 0
          except DatabaseError, e:
            LOG.info("Non Fatal Exception: %s: %s" % (e.__class__.__name__, e))
            errorCount += 1
            if errorCount > 9 and deleteRecords == 1:
              raise
            if deleteRecords > 100:
              deleteRecords = max(deleteRecords - 100, 1)
            else:
              deleteRecords = max(deleteRecords - 10, 1)
            LOG.info("Decreasing max delete records for Workflows to: %s" % deleteRecords)
          totalWorkflows = Workflow.objects.filter(name='', last_modified__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)


        LOG.info("Cleaning up anything in the Hue tables desktop_document2 older than %s old" % options['keep_days'])

        history_docs = Document2.objects.filter(is_history=True, last_modified__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)
        LOG.info("Deleting %s doc2 entries from desktop_document2." % history_docs.count())
        Document2.objects.filter(pk__in = list(history_docs)).delete()

        errorCount = 0
        checkCount = 0
        resets = 0
        deleteRecords = deleteRecordsBase

        totalSessions = Session.objects.filter(last_used__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)
        LOG.info("Looping through old Query Sessions. %s sessions to be deleted." % totalSessions.count())
        while totalSessions.count():
          if deleteRecords < 30 and resets < resetMax:
            checkCount += 1
          if checkCount == resetCount:
            deleteRecords = deleteRecordsBase
            resets += 1
            checkCount = 0
          LOG.info("Sessions left: %s" % totalSessions.count())
          deleteSessions = Session.objects.filter(last_used__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)[:deleteRecords]
          try:
            Session.objects.filter(pk__in = list(deleteSessions)).delete()
            errorCount = 0
          except DatabaseError, e:
            LOG.info("Non Fatal Exception: %s: %s" % (e.__class__.__name__, e))
            errorCount += 1
            if errorCount > 9 and deleteRecords == 1:
              raise
            if deleteRecords > 100:
              deleteRecords = max(deleteRecords - 100, 1)
            else:
              deleteRecords = max(deleteRecords - 10, 1)
            LOG.info("Decreasing max delete records for Sessions to: %s" % deleteRecords)
          totalSessions = Session.objects.filter(name='', last_modified__lte=date.today() - timedelta(days=options['keep_days'])).values_list("id", flat=True)

        end = time.time()
        elapsed = (end - start)
        LOG.debug("Total time elapsed (seconds): %.2f" % elapsed)
