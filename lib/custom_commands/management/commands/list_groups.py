#!/usr/bin/env python
import os
import sys
import time
import datetime
import re
import logging

from django.core.management.base import BaseCommand, CommandError
from django.utils.translation import ugettext_lazy as _t, ugettext as _
from django.contrib.auth.models import User, Group

import desktop.conf

LOG = logging.getLogger(__name__)


class Command(BaseCommand):
    """
    Handler for listing groups and groups associated with a user
    """

    try:
        from optparse import make_option
        option_list = BaseCommand.option_list + (
            make_option("--username", help=_t("Groups this user belongs to . "),
                        action="store", default=None),
        )

    except AttributeError, e:
        baseoption_test = 'BaseCommand' in str(e) and 'option_list' in str(e)
        if baseoption_test:
            def add_arguments(self, parser):
                parser.add_argument("--username", help=_t("Groups this user belongs to."),
                                    action="store", default=None)
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
        try:
          if options['username'] != None:
            LOG.info("Listing groups for %s" % options['username'])
            user = User.objects.get(username = options['username'])
            groups = user.groups.all()
            for group in groups:
              LOG.info("%s" % group.name)
          else:
            LOG.info("Listing all groups")
            groups = Group.objects.all()
            for group in groups:
              LOG.info("%s" % group.name)

        except Exception as e:
            LOG.warn("EXCEPTION: Listing groups failed, %s" % e)


