#!/usr/bin/python
#Tries to guess typical concurrent users

import os
import re
import heapq
import optparse
import datetime
from collections import OrderedDict

parser = optparse.OptionParser()
parser.add_option('--log-dir',
    help='Location for log files. Defaults to /var/log/hue',
    dest='log_dir',
    default='/var/log/hue')
parser.add_option('--today',
    help="run estimate today's users.",
    action='store_true',
    default=False)
parser.add_option('--date',
    help='process logs on the specified date. In form of YYYY-MM-DD',
    dest='date',
    default=None)
parser.add_option('--last10',
    help='process logs for last 10 minutes.',
    action='store_true',
    default=False)
parser.add_option('--includejb',
    help='Include jobbrowser entries.',
    action='store_true',
    default=False)
parser.add_option('--increment',
    help='Increments to count users, hour, min10, day',
    dest='increment',
    default='day')

options, args = parser.parse_args()

if options.date:
  now = datetime.datetime.strptime(options.date, '%Y-%m-%d')
else:
  now = datetime.datetime.now()
  minus10 = now - datetime.timedelta(minutes=10)

date = now - datetime.timedelta(days=1999)
previous_date = now - datetime.timedelta(days=2000)
totalconcurrent = 0
userlist = []
numlist = []

regex = re.compile(
    #Example line
    #[20/Jun/2017 04:40:07 -0700] DEBUG    172.31.112.36 -anon- - "HEAD /desktop/debug/is_alive HTTP/1.1"
    r'\['
    r'(?P<date>'
      r'\d{2}/\w{3}/\d{4} ' # Parse Date in form of '25/Oct/2015'
      r'\d{2}:\d{2}:\d{2}'  # Parse Time in form of '12:34:56'
    r') '
    r'[-+]?\d{4}' # Ignore the timezone
    r'\] '
    r'(?P<level>\w+) +'
    r'(?P<ip>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) '
    r'(?P<user>\w+) '
    r'\S+ "' # Ignore unknown
    r'(?P<method>\w+) '
    r'(?P<url>\S+) '
)

for filename in sorted(os.listdir(options.log_dir), reverse=True):
   if not filename.startswith("access"):
      continue  # Only process access log files

   for line in open(options.log_dir + "/" + filename).xreadlines():
      if not line.startswith("["):
        continue # Only process lines that start with a date

      #Make sure this log entry is a user access
      m = regex.match(line)
      if m:
        previous_date = date
        date = datetime.datetime.strptime(m.group('date'), '%d/%b/%Y %H:%M:%S')

        if not options.includejb:
          if re.match(m.group('url'), '/jobbrowser/jobs/$'):
            continue

        if options.today:
          if \
              date.year != now.year or \
              date.month != now.month or \
              date.day != now.day:
            continue

        if options.last10:
          #Skip anything older than 10 mins ago
          if date < minus10:
            continue
        
        user = m.group('user')

        if previous_date.day == date.day:
          if not user == "-anon-":
            userlist.append(user)
        else:
          newuserlist = list(OrderedDict.fromkeys(userlist))
          userlist = []
          totalconcurrent = len(newuserlist)
          numlist.append(totalconcurrent)

newuserlist = list(OrderedDict.fromkeys(userlist))
totalconcurrent = len(newuserlist)
numlist.append(totalconcurrent)
#Sort the list and remove any unique values
numlist = sorted(set(numlist))
#Print the top 10 most concurrent counts
print "largest: %s" % heapq.nlargest(10, numlist)

