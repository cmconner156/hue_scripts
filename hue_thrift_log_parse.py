import sys
import re
import pprint

print "Number of arguments: %s" % len(sys.argv)
print "Argument List: %s" % str(sys.argv)

thrift_messages = {}
thrift_responses = {}
thrift_responses["count"] = 0
thrift_open = {}
thrift_open["count"] = 0
thrift_open_respones = {}

fmt_resp = re.compile(
    r'\[(?P<timestamp>.+?)\]\s+' # Save everything within [] to group timestamp
    r'(?P<class>.+?)\s+' # Save next word as class
    r'(?P<log_level>.+?)\s+' # Save next word as log level
    r'(?P<call_type>.+?)(\s\<class\s\')' # Save everything before \s<class\s or end of line to call_type,
    r'(?P<thrift_class>.+?)(\'\>\.)' #Save everything between class ' and '> as thrift_class
    r'(?P<thrift_method>.+?)(\sreturned\sin\s)' #Save everything between >. and returned in as thrift_method
    r'(?P<thrift_duration>.+?)(\:\s)' #Save everything between returned in and : as thrift_duration
    r'(?P<message>.+$)?' # if there was a \s:\s, save everything after it to group   message. This last group is optional
)

fmt_req = re.compile(
    r'\[(?P<timestamp>.+?)\]\s+' # Save everything within [] to group timestamp
    r'(?P<class>.+?)\s+' # Save next word as class
    r'(?P<log_level>.+?)\s+' # Save next word as log level
    r'(?P<call_type>.+?)(\s\<class\s\')' # Save everything before \s<class\s or end of line to call_type,
    r'(?P<thrift_class>.+?)(\'\>\.)' #Save everything between class ' and '> as thrift_class
    r'(?P<thrift_method>.+?)(\()' #Save everything between >. and returned in as thrift_method
    r'(?P<thrift_junk>.+?)(secret\=\')' #Save everything between method and secret= as thrift_junk)
    r'(?P<thrift_secret>.+?)(\'\,\sguid\=\')' #Save everything after secret and before guid= as thrift_secret)
    r'(?P<thrift_guid>.+?)(\'\)\)\,)' #save everything from guid= to ')), as thrift_guid
    r'(?P<message>.+$)?' # if there was a \s:\s, save everything after it to group   message. This last group is optional
)

fmt_req_execute = re.compile(
    r'\[(?P<timestamp>.+?)\]\s+' # Save everything within [] to group timestamp
    r'(?P<class>.+?)\s+' # Save next word as class
    r'(?P<log_level>.+?)\s+' # Save next word as log level
    r'(?P<call_type>.+?)(\s\<class\s\')' # Save everything before \s<class\s or end of line to call_type,
    r'(?P<thrift_class>.+?)(\'\>\.)' #Save everything between class ' and '> as thrift_class
    r'(?P<thrift_method>.+?)(\()' #Save everything between >. and returned in as thrift_method
    r'(?P<thrift_junk>.+?)(secret\=\')' #Save everything between method and secret= as thrift_junk)
    r'(?P<thrift_secret>.+?)(\'\,\sguid\=\')' #Save everything after secret and before guid= as thrift_secret)
    r'(?P<thrift_guid>.+?)(runAsync\=)' #save everything from guid= to ')), as thrift_guid
    r'(?P<thrift_runasync>.+?)(statement\=\")' #save everything after runAsync to , statement... as thrift_runasync
    r'(?P<thrift_statement>.+?)(\"\)\,\)\,\ kwargs)' #save everything after runAsync to kwargs as thrift_statement
    r'(?P<message>.+$)?' # if there was a \s:\s, save everything after it to group   message. This last group is optional
)

#[28/Apr/2016 23:21:34 +0000] thrift_util  DEBUG    Thrift call: <class 'TCLIService.TCLIService.Client'>.ExecuteStatement(args=(TExecuteStatementReq(confOverlay={},
# sessionHandle=TSessionHandle(sessionId=THandleIdentifier(secret='c\xa4\xb2\xec\xd2IN\x8f\xa16#\xa2\x93\x0c&\x14', guid='2\x90(\x1a\x1b\xdcFp\xae\xa93#\xe0m\xcb\xb6')),
#  runAsync=True, statement="SET page_category='PS Product page'"),), kwargs={})

fmt_resp_open = re.compile(
    r'\[(?P<timestamp>.+?)\]\s+' # Save everything within [] to group timestamp
    r'(?P<class>.+?)\s+' # Save next word as class
    r'(?P<log_level>.+?)\s+' # Save next word as log level
    r'(?P<call_type>.+?)(\s\<class\s\')' # Save everything before \s<class\s or end of line to call_type,
    r'(?P<thrift_class>.+?)(\'\>\.)' #Save everything between class ' and '> as thrift_class
    r'(?P<thrift_method>.+?)(\sreturned\sin\s)' #Save everything between >. and returned in as thrift_method
    r'(?P<thrift_duration>.+?)(\:\s)' #Save everything between returned in and : as thrift_duration
    r'(?P<thrift_junk>.+?)(secret\=\')' # Save everything between method and secret= as thrift_junk
    r'(?P<thrift_secret>.+?)(\'\,\sguid\=\')' # Save everything after secret and before guid= as thrift_secret)
    r'(?P<thrift_guid>.+?)(\'\)\)\,)' #save everything from guid= to ')), as thrift_guid
    r'(?P<message>.+$)?' # if there was a \s:\s, save everything after it to group   message. This last group is optional
)

fmt_req_open = re.compile(
    r'\[(?P<timestamp>.+?)\]\s+' # Save everything within [] to group timestamp
    r'(?P<class>.+?)\s+' # Save next word as class
    r'(?P<log_level>.+?)\s+' # Save next word as log level
    r'(?P<call_type>.+?)(\s\<class\s\')' # Save everything before \s<class\s or end of line to call_type,
    r'(?P<thrift_class>.+?)(\'\>\.)' #Save everything between class ' and '> as thrift_class
    r'(?P<thrift_method>.+?)(\()' #Save everything between >. and returned in as thrift_method
    r'(?P<thrift_junk>.+?)(username\=\')' #Save everything between method and secret= as thrift_junk)
    r'(?P<thrift_username>.+?)(\'\,)' #Save username= into thrift_username)
    r'(?P<thrift_junk2>.+?)(client_protocol\=)' #Save everything after username as thrift_junk2)
    r'(?P<thrift_client_proto>.+?)(\,\ configuration=\{\'hive.server2.proxy.user\'\:\ u\')' #Save everything after client_protocol and before , config... as thrift_client_proto)
    r'(?P<thrift_proxy_user>.+?)(\'\})' #save everything after hive.server2.proxy.user and before '} as thrift_proxy_user
    r'(?P<message>.+$)?' # if there was a \s:\s, save everything after it to group   message. This last group is optional
)

f = open(sys.argv[1], 'r')

for line in f:
    if "Thrift call" in line and not "GetLog" in line and not "GetOperationStatus" in line:
        if fmt_resp_open.match(line):
            blah = "blah1"
#            print "fmt_resp_open:"
#            log_response = fmt_resp_open.search(line).groupdict()
#            if log_response["thrift_secret"] in thrift_messages:
#                thrift_messages[log_response["thrift_secret"]]["count"] = thrift_messages[log_response["thrift_secret"]]["count"] + 1
#                querystring = "query%s" % thrift_messages[log_response["thrift_secret"]]["count"]
#                print "fmt_resp_open: adding entry %s" % querystring
#                thrift_messages[log_response["thrift_secret"]][querystring] = log_response
#            else:
#                thrift_messages[log_response["thrift_secret"]] = {}
#                thrift_messages[log_response["thrift_secret"]]["count"] = 0
#                querystring = "query%s" % thrift_messages[log_response["thrift_secret"]]["count"]
#                print "fmt_resp_open: adding entry %s" % querystring
#                thrift_messages[log_response["thrift_secret"]][querystring] = log_response
        elif fmt_req_open.match(line):
#            print "fmt_req_open:"
            log_response = fmt_req_open.search(line).groupdict()
            querystring = "query%s" % thrift_open["count"]
            thrift_responses["count"] = thrift_responses["count"] + 1
            thrift_open[querystring] = log_response
        elif fmt_req_execute.match(line):
#            print "fmt_req_execute:"
            log_response = fmt_req_execute.search(line).groupdict()
            if log_response["thrift_secret"] in thrift_messages:
                thrift_messages[log_response["thrift_secret"]]["count"] = thrift_messages[log_response["thrift_secret"]]["count"] + 1
                querystring = "query%s" % thrift_messages[log_response["thrift_secret"]]["count"]
#                print "fmt_req_execute: adding entry %s" % querystring
                thrift_messages[log_response["thrift_secret"]][querystring] = log_response
            else:
                thrift_messages[log_response["thrift_secret"]] = {}
                thrift_messages[log_response["thrift_secret"]]["count"] = 0
                querystring = "query%s" % thrift_messages[log_response["thrift_secret"]]["count"]
#                print "fmt_req_execute: adding entry %s" % querystring
                thrift_messages[log_response["thrift_secret"]][querystring] = log_response
        elif fmt_req.match(line):
#            print "fmt_req:"
            log_response = fmt_req.search(line).groupdict()
            if log_response["thrift_secret"] in thrift_messages:
                thrift_messages[log_response["thrift_secret"]]["count"] = thrift_messages[log_response["thrift_secret"]]["count"] + 1
                querystring = "query%s" % thrift_messages[log_response["thrift_secret"]]["count"]
#                print "fmt_req: adding entry %s" % querystring
                thrift_messages[log_response["thrift_secret"]][querystring] = log_response
            else:
                thrift_messages[log_response["thrift_secret"]] = {}
                thrift_messages[log_response["thrift_secret"]]["count"] = 0
                querystring = "query%s" % thrift_messages[log_response["thrift_secret"]]["count"]
#                print "fmt_req: adding entry %s" % querystring
                thrift_messages[log_response["thrift_secret"]][querystring] = log_response
        elif fmt_resp.match(line):
            log_response = fmt_resp.search(line).groupdict()
            querystring = "query%s" % thrift_responses["count"]
            thrift_responses["count"] = thrift_responses["count"] + 1
            thrift_responses[querystring] = log_response


print "thrift_messages:"
pprint.pprint(thrift_messages, width=1)
print ""
print "thrift_open:"
pprint.pprint(thrift_open, width=1)
print ""
print "thrift_responses:"
pprint.pprint(thrift_responses, width=1)








#log = '[2013-Mar-05 18:21:45.415053] (4139) <ModuleA> [DEBUG]  Message Desciption : An example message!'
        #log = "[28/Apr/2016 20:41:56 +0000] thrift_util  DEBUG    Thrift call <class 'TCLIService.TCLIService.Client'>.GetOperationStatus returned in 5435ms: TGetOperationStatusResp(status=TStatus(errorCode=None, errorMessage=None, sqlState=None, infoMessages=None, statusCode=0), operationState=1, errorMessage=None, sqlState=None, errorCode=None)"

        #match = fmt_resp.search(log)

        #print match.groupdict()

        #exit()










#        if "returned" in line:
#        [28/Apr/2016 20:41:56 +0000] thrift_util  DEBUG    Thrift call <class 'TCLIService.TCLIService.Client'>.GetOperationStatus returned in 5435ms: TGetOperationStatusResp(status=TStatus(errorCode=None, errorMessage=None, sqlState=None, infoMessages=None, statusCode=0), operationState=1, errorMessage=None, sqlState=None, errorCode=None)
#   	    print "%s %s %s %s %s %s" % (tokens[0], tokens[1], tokens[8], tokens[11], tokens[13], tokens[18])
#	else:
#	[28/Apr/2016 20:41:56 +0000] thrift_util  DEBUG    Thrift call: <class 'TCLIService.TCLIService.Client'>.GetLog(args=(TGetLogReq(operationHandle=TOperationHandle(hasResultSet=True, modifiedRowCount=None, operationType=0, operationId=THandleIdentifier(secret='\x15Ki)\x8bhG\xb0\xba\x02\xe8\xe3\x0b\xd9\x9e\xfb', guid='\x1a\xc4\x8a\xee~\x11G\x99\xb1U\xbd\xcc\x95p\xe4\x82'))),), kwargs={})
#	    print "%s %s %s %s %s %s" % (tokens[0], tokens[1], tokens[8], tokens[11], tokens[12])

#	    stderr.log.1:
