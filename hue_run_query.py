import os, sys, time
if len(sys.argv) > 1:
  sys.path.insert(0, sys.argv[1])
else:
  sys.path.insert(0, '/opt/cloudera/parcels/CDH/lib/hue')

if len(sys.argv) > 2:
  username = sys.argv[2]
else:
  username = 'admin'

if len(sys.argv) > 3:
  query = sys.argv[3]
else:
  query = 'select count(*) from default.sample_07'

from django.conf import settings

os.environ['DJANGO_SETTINGS_MODULE']='desktop.settings'

from beeswax.server import dbms
from django.contrib.auth.models import User
hue, created = User.objects.get_or_create(username=username)

db = dbms.get(hue)
db.get_tables()

query = db.execute_statement(query)

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
