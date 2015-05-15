#!/usr/bin/python
#Tries to guess typical concurrent users

import os
import re
import heapq
from collections import OrderedDict

hue_log_dir = "/var/log/hue"
date = "temp"
userlist = [];
numlist = [];

for filename in sorted(os.listdir(hue_log_dir), reverse=True):
   if not filename.startswith("access"):
      continue  # Only process access log files
   for line in open(hue_log_dir + "/" + filename).xreadlines():
      if not line.startswith("["):
        continue # Only process lines that start with a date
      parts = line.split(" ")
      #Make sure this log entry is a user access
      if len(parts) > 8:
        ip = parts[8]
        user = parts[9]
        previous_date = date
        date_parts = line.split("[")
        date = date_parts[1]
        date_parts = date.split("]")
        date = date_parts[0]
        date_parts = date.split(":")
        date = "%s:%s" % (date_parts[0], date_parts[1])
        #Make sure line has IP address so that we know it's a user
        if re.match('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', ip) != None:
          if previous_date == date:
            if not user == "-anon-":
              userlist.append(user)
          else:
            newuserlist = list(OrderedDict.fromkeys(userlist))
            userlist = []
            totalconcurrent = len(newuserlist)
            numlist.append(totalconcurrent)
#            print "totalconcurrent: %s newuserlist: %s" % (totalconcurrent, newuserlist)

#Sort the list and remove any unique values
numlist = sorted(set(numlist))
#Print the top 10 most concurrent counts
print "largest: %s" % heapq.nlargest(10, numlist)

