#!/opt/cloudera/parcels/CDH/lib/hue/build/env/bin/python
import os, sys, time
sys.path.insert(0, '/opt/cloudera/parcels/CDH/lib/hue')
#sys.path.append('/opt/cloudera/parcels/CDH/lib/hue')
from django.conf import settings

os.environ['DJANGO_SETTINGS_MODULE']='desktop.settings'

from beeswax.server import dbms
from django.contrib.auth.models import User
hue, created = User.objects.get_or_create(username='admin')

db = dbms.get(hue)
db.get_tables()

query = db.execute_statement('select * from sample_07')

while True:
  ret = db.get_state(query.get_handle())
  if ret.key!='running':
    break
  time.sleep(1)
  print "waiting for query execution"

result = db.fetch(query.get_handle())

i=0
for row in result.rows():
  print row
  if i>100:
    break
  i += 1

print db.get_log(query.get_handle())
