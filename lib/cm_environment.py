import os
import sys
import logging
import subprocess
logging.basicConfig()
LOG = logging.getLogger(__name__)

class Configurator(object):
  """
  Class to configure Hue environment from CM
  """

  def set_cm_environment(self):
    """
    Collect environment from CM supervisor
    """
    cm_config_file = '/etc/cloudera-scm-agent/config.ini'
    cm_supervisor_dir = '/var/run/cloudera-scm-agent'
    if os.path.isfile(cm_config_file):
      import ConfigParser
      from ConfigParser import NoOptionError
      config = ConfigParser.RawConfigParser()
      config.read(cm_config_file)
#     cm_supervisor_dir = config.get('General', 'agent_wide_credential_cache_location')

      try:
        supervisor_process = subprocess.Popen('ps -ef | grep [s]upervisord | awk \'{print $2}\'', shell=True, stdout=subprocess.PIPE)
        supervisor_pid = supervisor_process.communicate()[0].split('\n')[0]
        cm_supervisor_dir = os.path.realpath('/proc/%s/cwd' % supervisor_pid)
      except Exception, e:
        LOG.exception("Unable to get valid supervisord, make sure you are running as root and make sure the CM supervisor is running")    

      #Parse CM supervisor include file for Hue and set env vars
      cm_supervisor_dir = cm_supervisor_dir + '/include'
      cm_agent_run_dir = os.path.dirname(cm_supervisor_dir)
      hue_env_conf = None
      envline = None
      cm_hue_string = "HUE_SERVER"

      for file in os.listdir(cm_supervisor_dir):
        if cm_hue_string in file:
          hue_env_conf = file

      if not hue_env_conf == None:
        if os.path.isfile(cm_supervisor_dir + "/" + hue_env_conf):
          hue_env_conf_file = open(cm_supervisor_dir + "/" + hue_env_conf, "r")
          LOG.info("Setting CM managed environment using supervisor include: %s" % hue_env_conf_file)
          for line in hue_env_conf_file:
            if "environment" in line:
              envline = line
            if "directory" in line:
              empty, hue_conf_dir = line.split("directory=")
              os.environ["HUE_CONF_DIR"] = hue_conf_dir.rstrip()
              sys.path.append(os.environ["HUE_CONF_DIR"])
  
      if not envline == None:
        empty, environment = envline.split("environment=")
        for envvar in environment.split(","):
          if "HADOOP_C" in envvar or "PARCEL" in envvar or "DESKTOP" in envvar or "ORACLE" in envvar or "LIBRARY" in envvar:
            envkey, envval = envvar.split("=")
            envval = envval.replace("'", "").rstrip()
            os.environ[envkey] = envval

      if "PARCELS_ROOT" in os.environ:
        parcel_dir = os.environ["PARCELS_ROOT"]
      else:
        parcel_dir = "/opt/cloudera/parcels"

      oracle_instant_client = "%s/ORACLE_INSTANT_CLIENT" % parcel_dir
      ld_library_path = "%s/instantclient_11_2" % oracle_instant_client
      os.environ["ORACLE_HOME"] = ld_library_path
      if 'LD_LIBRARY_PATH' in os.environ:
        os.environ["LD_LIBRARY_PATH"] = "%s:%s" % (os.environ["LD_LIBRARY_PATH"], ld_library_path)
      else:
        os.environ["LD_LIBRARY_PATH"] = ld_library_path

      sys.path.append(os.environ["LD_LIBRARY_PATH"])

  def reload_with_cm_env(self):
    try:
      from django.db.backends.oracle.base import Oracle_datetime
    except:
      if 'LD_LIBRARY_PATH' in os.environ and "ORACLE_HOME" in os.environ:
        LOG.warn("We need to reload the process to include LD_LIBRARY_PATH and ORACLE_HOME")
        try:
          os.execv(sys.argv[0], sys.argv)
        except Exception, exc:
          LOG.warn('Failed re-exec:', exc)
          sys.exit(1)

    LOG.warn("Successfully reloaded: LD_LIBRARY_PATH: %s" % os.environ['LD_LIBRARY_PATH'])
    LOG.warn("Successfully reloaded: ORACLE_HOME: %s" % os.environ['ORACLE_HOME'])

