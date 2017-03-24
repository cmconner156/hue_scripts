import json
import re
import logging

from desktop.models import Document2
DOC2_NAME_INVALID_CHARS = "[<>/{}[\]~`u'\xe9'u'\xfa'u'\xf3'u'\xf1'u'\xed']"

LOG = logging.getLogger(__name__)

def removeInvalidChars(fixString):
  return re.sub(DOC2_NAME_INVALID_CHARS, '', fixString) 

def findMatchingQuery(user, id, name, query, include_history=False, all=False, values=False):
#Returns list of matching queries.  If all = False
#returns at first found for speed
  name = removeInvalidChars(name)
  LOG.debug("finding queries that match name: %s" % name)
  documents = getSavedQueries(user=user, name=name, include_history=include_history)
  matchdocs = []
  matchvalues = []
   
  for doc in documents:
    if all == True or not matchdocs:
      matchdata = json.loads(doc.data)
      matchname = removeInvalidChars(doc.name)
      if 'snippets' in matchdata:
        matchquery = matchdata['snippets'][0]['statement_raw']
        if name == matchname and id != doc.id:
          if query == matchquery:
            LOG.debug("MATCHED QUERY: name: %s: id: %s" % (name, id))
            matchdocs.append(doc) 
            matchvalues.append(doc.id)

  if values == False:
    LOG.debug("returning %s matching docs" % len(matchdocs))
    return matchdocs
  else:
    LOG.debug("returning %s matching doc ids" % len(matchdocs))
    return matchvalues


def getSavedQueries(user, name=None, include_history=False):
#mimic api call to get saved queries
  perms = 'both'
  include_trashed = False
  flatten = True
  if name:
    documents = Document2.objects.filter(name=name, owner=user, type__in=['query-hive', 'query-impala'], is_history=include_history)
    LOG.debug("getting queries that match name: %s" % name)
  else:
    documents = Document2.objects.documents(
      user=user,
      perms=perms,
      include_history=include_history,
      include_trashed=include_trashed
    )
    LOG.debug("getting all queries, history is %s" % include_history)

  return documents


