#!/usr/bin/env python
import os
import time
import uuid

from importlib import import_module

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.utils.translation import ugettext_lazy as _t, ugettext as _
from datetime import date, timedelta
from django.db.utils import DatabaseError
import desktop.conf
from desktop.models import Document2
from django.contrib.auth.models import User
from desktop.auth.backend import find_or_create_user
import logging
import logging.handlers


import desktop.conf

LOG = logging.getLogger(__name__)


class Command(BaseCommand):
  """
  Handler for purging old Query History, Workflow documents and Session data
  """

  try:
    from optparse import make_option
    option_list = BaseCommand.option_list + (
      make_option("--keep-days", help=_t("Number of days of history data to keep."),
          action="store",
          type=int,
          default=30),
    )

  except AttributeError, e:
    baseoption_test = 'BaseCommand' in str(e) and 'option_list' in str(e)
    if baseoption_test:
      def add_arguments(self, parser):
        parser.add_argument("--keep-days", help=_t("Number of days of history data to keep."),
          action="store",
          type=int,
          default=30)
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
    LOG.info("Removing any orphaned docs")

    start = time.time()

    totalUsers = User.objects.filter().values_list("id", flat=True)
    totalDocs = Document2.objects.exclude(owner_id__in=totalUsers)
#    deleteDirs = Document2.objects.exclude(owner_id__in=totalUsers).filter(type__in('directory'))
    docstorage_id = "docstorage" + str(uuid.uuid4())
    docstorage = find_or_create_user(docstorage_id[:30])

    for doc in totalDocs:
      if doc.type == "oozie-workflow2":
        name = doc.name
        doc2 = doc2.copy(name=name, owner=docstorage)
        print "migrating workflow: %s : %s : %s : %s : to user: %s" % (doc2.name, doc2.type, doc2.owner_id, doc2.parent_directory, docstorage_id)


    for doc in totalDocs:
      if doc.type == "directory":
        print "deleting doc: %s : %s : %s" % (doc.name, doc.type, doc.owner_id)
#      doc.delete()





    end = time.time()
    elapsed = (end - start)
    LOG.debug("Total time elapsed (seconds): %.2f" % elapsed)



