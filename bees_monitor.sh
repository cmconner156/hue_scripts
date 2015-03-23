#/bin/sh

API_URL='localhost:7180'
CLUSTER='Cluster 1 - CDH4'
EMAIL_TO='root'

curl -u admin "http://$API_URL/api/v2/clusters/$CLUSTER/services" > new_status
diff new_status old_status > last_change
if [ $? -ne 0 ]
then
cat last_change new_status | mail -s "Status of $CLUSTER has Changed" $EMAIL_TO
fi

mv new_status old_status
