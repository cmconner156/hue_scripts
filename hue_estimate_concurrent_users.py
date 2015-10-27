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
    help='process longs on the specified date. In form of YYYY-MM-DD',
    dest='date',
    default=None)

options, args = parser.parse_args()

if options.date:
  now = datetime.datetime.strptime(options.date, '%Y-%m-%d')
elif options.today:
  now = datetime.datetime.now()
else:
  now = None

print now.year, now.month, now.day

date = None
userlist = []
numlist = []

regex = re.compile(
    r'\['
    r'(?P<date>'
      r'\d{2}/\w{3}/\d{4} ' # Parse Date in form of '25/Oct/2015'
      r'\d{2}:\d{2}:\d{2}'  # Parse Time in form of '12:34:56'
    r') '
    r'[-+]?\d{4}' # Ignore the timezone
    r'\] '
    r'(?P<level>\w+) +'
    r'(?P<ip>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) '
    r'(?P<user>\w+)'
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

        if now is not None:
          if \
              date.year != now.year or \
              date.month != now.month or \
              date.day != now.day:
            continue

        user = m.group('user')

        if previous_date == date:
          if not user == "-anon-":
            userlist.append(user)
        else:
          newuserlist = list(OrderedDict.fromkeys(userlist))
          userlist = []
          totalconcurrent = len(newuserlist)
          numlist.append(totalconcurrent)
#         print "totalconcurrent: %s newuserlist: %s" % (totalconcurrent, newuserlist)

#Sort the list and remove any unique values
numlist = sorted(set(numlist))
#Print the top 10 most concurrent counts
print "largest: %s" % heapq.nlargest(10, numlist)

