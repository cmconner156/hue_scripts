#!/usr/bin/env python2.6
import os; activate_this=os.path.join(os.path.dirname(os.path.realpath('/usr/lib64/cmf/agent/build/env/bin/activate_this.py')), 'activate_this.py'); execfile(activate_this, dict(__file__=activate_this)); del activate_this
import sys

script_dir = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, script_dir + '/lib')

import logging
import argparse
import re
import time
from adapter_factory import AdapterFactory
from cmf.safety_valve import SafetyValve
from cmf.monitor.monitor_properties import ConfParser
from cmf.monitor import conf
from cmf_test.monitor import make_config_file
from hue_adapters import _HueIsAliveCollector

parser = argparse.ArgumentParser()

parser.add_argument('-l', action='store', dest='log_dir', default='/var/log/hue',
                    help='Hue log directory')

parser.add_argument('-s', action='store', dest='sleep_time', default=20,
                    help='Amount of time to sleep between checks')

results = parser.parse_args()
log_dir = results.log_dir


LOG = logging.getLogger(__name__)
LOG.setLevel(logging.DEBUG)

ch = logging.StreamHandler(sys.stdout)
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
LOG.addHandler(ch)

tokenize = re.compile(r'(\d+)|(\D+)').findall
def natural_sortkey(string):          
    return tuple(int(num) if num else alpha for num, alpha in tokenize(string))

cm_run_path = '/var/run/cloudera-scm-agent/process/'
cm_run_directory = os.path.dirname(cm_run_path)
script_end_file = log_dir + '/' + os.path.basename(__file__).split('.')[0] + '.end'
if os.path.exists(cm_run_directory):
  for path in sorted(os.listdir(cm_run_directory), key=natural_sortkey):
    if 'HUE_SERVER' in path:
      hue_conf_dir = cm_run_directory + '/' + path
else:
  hue_conf_dir='/etc/hue/conf'

http_host='localhost'
http_port='8888'
ssl_enable='false'

hue_conf_file = hue_conf_dir + '/hue.ini'
if os.path.exists(hue_conf_file):
  with open(hue_conf_file) as f:
    for line in f:
      line.strip('\n\r')
      if "http_host" in line:
        empty, http_host = line.split('=')
      if "http_port" in line:
        empty, http_port = line.split('=')
      if 'ssl_certificate' in line:
        ssl_enable = 'true'

hue_conf_file = hue_conf_dir + '/hue_safety_valve.ini'
if os.path.exists(hue_conf_file):
  with open(hue_conf_file) as f:
    for line in f:
      line.strip('\n\r')
      if "http_host" in line:
        empty, http_host = line.split('=')
      if "http_port" in line:
        empty, http_port = line.split('=')
      if 'ssl_certificate' in line:
        ssl_enable = 'true'

hue_conf_file = hue_conf_dir + '/hue_safety_valve_server.ini'
if os.path.exists(hue_conf_file):
  with open(hue_conf_file) as f:
    for line in f:
      line.strip('\n\r')
      if "http_host" in line:
        empty, http_host = line.split('=')
      if "http_port" in line:
        empty, http_port = line.split('=')
      if 'ssl_certificate' in line:
        ssl_enable = 'true'

metrics_dir = log_dir + "/metrics-hue_server"
sample_file = metrics_dir + "/metrics.log"

conf_dir = make_config_file(
"""[hue_server]
role_name = hue-is-alive-test-1
service_name = hue_is_alive_test
service_version = 5
service_release = 5.8.0
http_host = %s
http_port = %s
ssl_enable = %s
log_dir = %s
monitored_directories = %s
collect_interval = 1.0
location=%s
""" % (http_host, http_port, ssl_enable, log_dir, metrics_dir, sample_file))

metrics_path = os.path.join(conf_dir, conf.SERVICE_METRICS_PROPERTIES)
file(metrics_path, 'w').write(
"""{
  "HUE_SERVER" : {
    "66666" : {
      "source" : "desktop.auth.oauth.authentication-time::99_percentile"
    },
    "66667" : {
      "source" : "python.threads.count::value"
    },
    "66668" : {
      "source" : "desktop.requests.exceptions.count::count"
    }
  }
}
""")


conf_parser = ConfParser(conf_dir, conf.CLOUDERA_MONITOR_PROPERTIES)
adapter = AdapterFactory().make_adapter("HUE", "HUE_SERVER", SafetyValve())
adapter._is_alive_collector = _HueIsAliveCollector(adapter)
collector = adapter.get_adapter_specific_collectors()[0]
collector.update_with_conf(conf_parser)
LOG.info("CHRIS:file: %s" % script_end_file)
LOG.info("CHRIS:exists: %s" % os.path.exists(script_end_file))
while not os.path.exists(script_end_file):
  LOG.info(__name__ + ": collector.collect_and_parse")
  collector.collect_and_parse(conf_parser)
  time.sleep(int(results.sleep_time))


