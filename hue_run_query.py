import os, sys, time

if len(sys.argv) > 1:
  LOGFILE = sys.argv[1]
else:
  LOGFILE = "/var/log/hue/hue_run_query"

if len(sys.argv) > 2:
  sys.path.insert(0, sys.argv[2])
else:
  sys.path.insert(0, '/opt/cloudera/parcels/CDH/lib/hue')

if len(sys.argv) > 3:
  username = sys.argv[3]
else:
  username = 'admin'

if len(sys.argv) > 4:
  query = sys.argv[4]
else:
  query = 'default.sample_07'

ENV_HUE_PROCESS_NAME = "HUE_PROCESS_NAME"
ENV_DESKTOP_DEBUG = "DESKTOP_DEBUG"
script_dir = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, script_dir + '/lib')

from django.conf import settings
os.environ['DJANGO_SETTINGS_MODULE']='desktop.settings'
from beeswax.server import dbms
from beeswax.conf import HIVE_SERVER_HOST
from django.contrib.auth.models import User
import logging
import log

if ENV_HUE_PROCESS_NAME not in os.environ:
  _proc = os.path.basename(len(sys.argv) > 1 and sys.argv[1] or sys.argv[0])
  os.environ[ENV_HUE_PROCESS_NAME] = _proc

os.environ[ENV_DESKTOP_DEBUG] = 'True'
log.basic_logging(os.environ[ENV_HUE_PROCESS_NAME])
log.fancy_logging()

logging.debug("Running query: %s" % query)
logging.debug("Running as user: %s" % username)

hue, created = User.objects.get_or_create(username=username)

logging.debug("Running query host: %s" % HIVE_SERVER_HOST)

start = time.time()
db = dbms.get(hue)
db.get_tables()

executequery = query
query = db.execute_statement(executequery)
logging.debug(db.get_log(query.get_handle()))

while True:
  ret = db.get_state(query.get_handle())
  logging.debug("ret: %s" % ret)
  logging.debug("ret.key: %s" % ret.key)
  if ret.key!='running':
    break
  time.sleep(1)
  logging.debug("Waiting for query execution")

result = db.fetch(query.get_handle())

i=0
for row in result.rows():
  logging.debug("row: %s" % row)
  if i>100:
    break
  i += 1

logging.debug(db.get_log(query.get_handle()))
end = time.time()
elapsed = (end - start) / 60
logging.debug("Time elapsed (minutes): %.2f" % elapsed)

