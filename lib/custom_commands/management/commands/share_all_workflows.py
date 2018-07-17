#!/usr/bin/env python
import os
import sys

from optparse import make_option

from django.core.management.base import BaseCommand, CommandError
from django.utils.translation import ugettext_lazy as _t, ugettext as _
import desktop.conf
from desktop.models import Document2
from django.contrib.auth.models import User, Group
import desktop.conf

import logging
import logging.handlers

LOG = logging.getLogger(__name__)


class Command(BaseCommand):
    """
    Handler for purging old Query History, Workflow documents and Session data
    """

    option_list = BaseCommand.option_list + (
        make_option("--shareusers", help=_t("Comma separated list of users to share all workflows with."),
                    action="store"),
        make_option("--sharegroups", help=_t("Comma separated list of groups to share all workflows with."),
                    action="store"),
        make_option("--permissions", help=_t("Comma separated list of permissions for the users and groups."
                                             "read, write or read,write"), action="store"),
    )


    def handle(self, *args, **options):

        LOG.warn("HUE_CONF_DIR: %s" % os.environ['HUE_CONF_DIR'])
        LOG.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
        LOG.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
        LOG.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
        LOG.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
        LOG.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))

        if not options['shareusers'] and not options['sharegroups']:
            print "You must set either shareusers or sharegroups or both"
            sys.exit(1)

        if not options['permissions']:
            print "permissions option required either read, write or read,write"
            sys.exit(1)

        if options['shareusers']:
            users = options['shareusers'].split(",")
        else:
            users = []

        if options['sharegroups']:
            groups = options['sharegroups'].split(",")
        else:
            groups = []

        perms = options['permissions'].split(",")

        LOG.info("Setting permissions %s on all workflows for users: %s" % (perms, users))
        LOG.info("Setting permissions %s on all workflows for groups: %s" % (perms, groups))

        users = User.objects.filter(username__in=users)
        groups = Group.objects.filter(name__in=groups)

        doc_types = ['oozie-workflow2', 'oozie-coordinator2', 'oozie-bundle2']

        oozie_docs = Document2.objects.filter(type__in=doc_types)

        for perm in perms:
            if perm in ['read', 'write']:
                print "perm: %s" % perm
                for oozie_doc in oozie_docs:
                    owner = User.objects.get(id = oozie_doc.owner_id)
                    read_perms = oozie_doc.to_dict()['perms']['read']
                    write_perms = oozie_doc.to_dict()['perms']['write']

                    read_users = []
                    write_users = []
                    read_groups = []
                    write_groups = []

                    LOG.warn("read_perms: %s" % read_perms)
                    for user in read_perms['users']:
                        read_users.append(user['id'])

                    for group in read_perms['groups']:
                        read_groups.append(group['id'])

                    for user in write_perms['users']:
                        write_users.append(user['id'])

                    for group in write_perms['groups']:
                        write_groups.append(group['id'])

                    for user in users:
                        if perm == 'read':
                            read_users.append(user['id'])

                        if perm == 'write':
                            write_users.append(user['id'])

                    for group in groups:
                        if perm == 'read':
                            read_groups.append(group['id'])

                        if perm == 'write':
                            write_groups.append(group['id'])

                    if perm == 'read':
                        users = User.objects.in_bulk(read_users)
                        groups = Group.objects.in_bulk(read_groups)

                    if perm == 'write':
                        users = User.objects.in_bulk(write_users)
                        groups = Group.objects.in_bulk(write_groups)

                    print "oozie_doc: %s" % oozie_doc
                    print "doc.share(owner = %s, name=%s, users=%s, groups=%s" % (owner, perm, users, groups)
                    oozie_doc.share(owner, name=perm, users=users, groups=groups)

