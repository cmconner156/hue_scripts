#!/usr/bin/env python
import os
import logging
import datetime
from pprint import pprint, pformat


from django.core.management.base import BaseCommand, CommandError
from django.contrib.auth.models import User
from django.db import models, transaction
from django.contrib.auth.models import User


import desktop.conf

LOG = logging.getLogger(__name__)


class Command(BaseCommand):
  """
  Handler for deleting duplicate UserPreference objects
  """

  def handle(self, *args, **options):
    LOG.warn("HUE_CONF_DIR: %s" % os.environ['HUE_CONF_DIR'])
    LOG.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
    LOG.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
    LOG.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
    LOG.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
    LOG.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))
    LOG.warn("Deleting duplicate User objects")

    users_dict = {}

    for user in User.objects.filter():
      user_list = [{'username': user.username, 'date_joined': user.date_joined, 'date_joined_readable': user.date_joined.strftime('%Y-%m-%d %H:%M:%S%z')}]
      users_dict[user.username.lower()] = user_list
      for usercompare in User.objects.filter():
        if usercompare.id != user.id and usercompare.username.lower() == user.username.lower():
          users_dict[user.username.lower()].append({'username': usercompare.username, 'date_joined': usercompare.date_joined, 'date_joined_readable': usercompare.date_joined.strftime('%Y-%m-%d %H:%M:%S%z')})

    LOG.warn("users_dict before update: %s" % pformat(users_dict, indent=4))

    for username in users_dict.keys():
      count = 0
      oldest_user = None
      oldest_date = None
      while count < len(users_dict[username]):
        if oldest_user is None:
          username1 = users_dict[username][count]['username']
          date1 = users_dict[username][count]['date_joined']
          username2 = users_dict[username][count + 1]['username']
          date2 = users_dict[username][count + 1]['date_joined']
          LOG.warn("Processing: count: %s: base: %s: with u1 %s : u2 %s" % (count, username, username1, username2))
          if date1 < date2:
            oldest_user = username1
            oldest_date = date1
            oldest_count = count
            users_dict[username][count + 1]["username"]=username2+"renamed"
          else:
            oldest_user = username2
            oldest_date = date2
            oldest_count = count + 1
            users_dict[username][count]["username"]=username1+"renamed"
        else:
          LOG.warn("Processing: count: %s: base: %s: with oldest_user %s : u2 %s" % (count, username, oldest_user, username2))
          username2 = users_dict[username][count]['username']
          date2 = users_dict[username][count]['date_joined']
          if username2.lower() == username and username2 != oldest_user:
            if oldest_date < date2:
              users_dict[username][count]["username"]=username2+"renamed"
            else:
              users_dict[username][oldest_count]["username"]=oldest_user+"renamed"
              oldest_user = username2
              oldest_date = date2
              oldest_count = count

        count = count + 1

    LOG.warn("users_dict after update: %s" % pformat(users_dict, indent=4))

    #        transaction.commit()

