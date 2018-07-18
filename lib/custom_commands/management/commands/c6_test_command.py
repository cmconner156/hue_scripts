#!/usr/bin/env python
import os
import sys
import time
import datetime
import re
import logging


from django.core.management.base import BaseCommand, CommandError
from django.utils.translation import ugettext_lazy as _t, ugettext as _
from django.contrib.auth.models import User

import desktop.conf

LOG = logging.getLogger(__name__)


class Command(BaseCommand):
    """
    Handler for running queries from Hue log with database_logging queries
    """

    def add_arguments(self, parser):
        parser.add_argument("--username", help=_t("User to delete case sensitive."),
                            action="store")


    def handle(self, *args, **options):
        LOG.warn("HUE_CONF_DIR: %s" % os.environ['HUE_CONF_DIR'])
        LOG.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
        LOG.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
        LOG.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
        LOG.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
        LOG.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))
        LOG.warn("Deleting user: %s" % options['username'])

        usernames = [ options['username'] ]
        try:
            User.objects.filter(username__in=usernames).delete()
        except Exception as e:
            LOG.warn("EXCEPTION: deleting user %s failed: %s" % (options['username'], e))


        LOG.debug("Done deleting user: %s" % options['username'] )


