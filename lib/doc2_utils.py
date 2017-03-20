import json
import logging
import time

from django.db import transaction
from django.utils.translation import ugettext as _

from desktop.lib.exceptions_renderable import PopupException
from django.core.exceptions import FieldError
from desktop.models import Document, DocumentPermission, DocumentTag, Document2, Directory, Document2Permission
from notebook.models import import_saved_beeswax_query

LOG = logging.getLogger(__name__)

def findMatchingQuery(user, name, query, include_history=False, all=False):
#Returns list of matching queries.  If all = False
#returns at first found for speed
  documents = getSavedQueries(user=user, include_history=include_history)
  matchdocs = []
   
  for doc in documents:
    if all == True or not matchdocs:
      matchdata = json.loads(doc.data)
      matchname = doc.name
      if matchdata:
        matchquery = matchdata['snippets'][0]['statement_raw']
        if name == matchname:
          if query == matchquery:
            matchdocs.append(doc) 
 
  return matchdocs



def getSavedQueries(user, name=None, include_history=False):
#mimic api call to get saved queries

  perms = 'both'
  include_trashed = False
  flatten = True

  documents = Document2.objects.documents(
    user=user,
    perms=perms,
    include_history=include_history,
    include_trashed=include_trashed
  )

  return documents



