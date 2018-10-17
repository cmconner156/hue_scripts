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
  def rename_user(self, rename_user=None, keep_user=None, count=None):
    new_username = rename_user + "renamed"
    LOG.warn("%s is newer than %s, renaming %s to %s" % (rename_user, keep_user, rename_user, new_username))
    self.users_dict[self.username][count]["username"] = new_username
    user_mod = User.objects.get(username=rename_user)
    user_mod.username = new_username
    user_mod.save()


  def log_users_list(self):
    users_unsorted = []
    for user in User.objects.filter():
      users_unsorted.append(user.username)

    users_sorted = sorted(users_unsorted, key=lambda s: s.lower())
    count = 0
    while count < len(users_sorted):
      LOG.warn("%s" % users_sorted[count])
      count = count + 1


  def handle(self, *args, **options):
    LOG.warn("HUE_CONF_DIR: %s" % os.environ['HUE_CONF_DIR'])
    LOG.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
    LOG.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
    LOG.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
    LOG.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
    LOG.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))
    LOG.warn("Deleting duplicate User objects")

    self.users_dict = {}
    self.username = None

    LOG.warn("users list before renames")
    self.log_users_list()


    for user in User.objects.filter():
      user_list = [{'username': user.username, 'date_joined': user.date_joined, 'date_joined_readable': user.date_joined.strftime('%Y-%m-%d %H:%M:%S%z')}]
      self.users_dict[user.username.lower()] = user_list
      for usercompare in User.objects.filter():
        if usercompare.id != user.id and usercompare.username.lower() == user.username.lower():
          self.users_dict[user.username.lower()].append({'username': usercompare.username, 'date_joined': usercompare.date_joined, 'date_joined_readable': usercompare.date_joined.strftime('%Y-%m-%d %H:%M:%S%z')})

    for username in self.users_dict.keys():
      self.username = username
      count = 0
      oldest_user = None
      oldest_date = None
      while count < len(self.users_dict[self.username]):
        current_dict = self.users_dict[self.username]
        if oldest_user is None:
          username1 = current_dict[count]['username']
          date1 = current_dict[count]['date_joined']
          username2 = current_dict[count + 1]['username']
          date2 = current_dict[count + 1]['date_joined']
          if date1 < date2:
            oldest_user = username1
            oldest_date = date1
            oldest_count = count
            self.rename_user(rename_user=username2, keep_user=oldest_user, count=count + 1)
          else:
            oldest_user = username2
            oldest_date = date2
            oldest_count = count + 1
            self.rename_user(rename_user=username1, keep_user=oldest_user, count=count)
        else:
          username2 = current_dict[count]['username']
          date2 = current_dict[count]['date_joined']
          if username2.lower() == self.username and username2 != oldest_user:
            if oldest_date < date2:
              self.rename_user(rename_user=username2, keep_user=oldest_user, count=count)
            else:
              self.rename_user(rename_user=oldest_user, keep_user=username2, count=oldest_count)
              oldest_user = username2
              oldest_date = date2
              oldest_count = count

        count = count + 1


    LOG.warn("users list after renames")
    self.log_users_list()

    #        transaction.commit()

