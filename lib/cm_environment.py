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
    hue_bin_dir = /usr/lib/hue
    cm_agent_process = subprocess.Popen('ps -ef | grep "[c]m agent\|[c]mf-agent" | awk \'{print $2}\'', shell=True, stdout=subprocess.PIPE)
    cm_agent_pid = cm_agent_process.communicate()[0].split('\n')[0]
#    cm_config_file = '/etc/cloudera-scm-agent/config.ini'
#    cm_supervisor_dir = '/var/run/cloudera-scm-agent'
    if cm_agent_pid != '':
#      import ConfigParser
#      from ConfigParser import NoOptionError
#      config = ConfigParser.RawConfigParser()
#      config.read(cm_config_file)
#     cm_supervisor_dir = config.get('General', 'agent_wide_credential_cache_location')

      try:
        supervisor_process = subprocess.Popen('ps -ef | grep [s]upervisord | awk \'{print $2}\'', shell=True, stdout=subprocess.PIPE)
        supervisor_pid = supervisor_process.communicate()[0].split('\n')[0]
        cm_supervisor_dir = os.path.realpath('/proc/%s/cwd' % supervisor_pid)
        if supervisor_pid == '':
          LOG.exception("This appears to be a CM enabled cluster and supervisord is not running")
          LOG.exception("Make sure you are running as root and CM supervisord is running")
          sys.exit(1)
      except Exception, e:
        LOG.exception("This appears to be a CM enabled cluster and supervisord is not running")
        LOG.exception("Make sure you are running as root and CM supervisord is running")
        sys.exit(1)

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
          if "HADOOP_C" in envvar or "PARCEL" in envvar or "DESKTOP" in envvar or "ORACLE" in envvar or "LIBRARY" in envvar or "CMF" in envvar:
            envkey, envval = envvar.split("=")
            envval = envval.replace("'", "").rstrip()
            os.environ[envkey] = envval

      if "PARCELS_ROOT" in os.environ:
        parcel_dir = os.environ["PARCELS_ROOT"]
      else:
        parcel_dir = "/opt/cloudera/parcels"

      hue_bin_dir = parcel_dir + "/CDH/lib/hue/build/env/bin"

      cloudera_config_script = None
      if os.path.isfile('/usr/lib64/cmf/service/common/cloudera-config.sh'):
        cloudera_config_script = '/usr/lib64/cmf/service/common/cloudera-config.sh'
      elif os.path.isfile('/opt/cloudera/cm-agent/service/common/cloudera-config.sh'):
        cloudera_config_script = '/opt/cloudera/cm-agent/service/common/cloudera-config.sh'

      JAVA_HOME = None
      if cloudera_config_script is not None:
        locate_java = subprocess.Popen(['bash', '-c', '. %s; locate_java_home' % cloudera_config_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for line in iter(locate_java.stdout.readline,''):
          if 'JAVA_HOME' in line:
            JAVA_HOME = line.rstrip().split('=')[1]

      if JAVA_HOME is not None:
        os.environ["JAVA_HOME"] = JAVA_HOME

      if "JAVA_HOME" not in os.environ:
        print "JAVA_HOME must be set and can't be found, please set JAVA_HOME environment variable"
        sys.exit(1)


      oracle_check_process = subprocess.Popen('grep -i oracle %s/hue*ini' % os.environ["HUE_CONF_DIR"], shell=True, stdout=subprocess.PIPE)
      oracle_check = oracle_check_process.communicate()[0]
      if not oracle_check == '':
        #Make sure we set Oracle Client if configured
        if "LD_LIBRARY_PATH" not in os.environ.keys():
          if "SCM_DEFINES_SCRIPTS" in os.environ.keys():
            for scm_script in os.environ["SCM_DEFINES_SCRIPTS"].split(":"):
              if "ORACLE" in scm_script:
                if os.path.isfile(scm_script):
                  oracle_source = subprocess.Popen(". %s; env" % scm_script, stdout=subprocess.PIPE, shell=True, executable="/bin/bash")
                  for line in oracle_source.communicate()[0].splitlines():
                    if "LD_LIBRARY_PATH" in line:
                      var, oracle_ld_path = line.split("=")
                      os.environ["LD_LIBRARY_PATH"] = oracle_ld_path

        if "LD_LIBRARY_PATH" not in os.environ.keys():
          print "LD_LIBRARY_PATH can't be found, if you are using ORACLE for your Hue database"
          print "then it must be set, if not, you can ignore"
          print "  export LD_LIBRARY_PATH=/path/to/instantclient"

    else:
      print "CM does not appear to be running on this server"
      print "If this is a CM managed cluster make sure the agent and supervisor are running"
      print "Running with /etc/hue/conf as the HUE_CONF_DIR"
      os.environ["HUE_CONF_DIR"] = "/etc/hue/conf"

    return hue_bin_dir

  def reload_with_cm_env(self):
    try:
      from django.db.backends.oracle.base import Oracle_datetime
    except:
      os.environ["SKIP_RELOAD"] = "True"
      if 'LD_LIBRARY_PATH' in os.environ:
        LOG.warn("We need to reload the process to include LD_LIBRARY_PATH for Oracle backend")
        try:
          os.execv(sys.argv[0], sys.argv)
        except Exception, exc:
          LOG.warn('Failed re-exec:', exc)
          sys.exit(1)

