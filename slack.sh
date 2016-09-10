#!/bin/bash -x

# config
slack_url='https://hooks.slack.com/services/XXX/XXXX/XXXXX'
slack_username='Zabbix'
channel="$1"
title="$2"
params="$3"
emoji=':ghost:'
timeout="5"
cmd_curl="/usr/bin/curl"
cmd_wget="/usr/bin/wget"

zabbix_baseurl="http://zabbix.example.com"
zabbix_username="yourzabbixusername"
zabbix_password="zabbixpassword"

# chart settings
chart_period=3600
chart_width=700
chart_height=390
chart_baseurl="${zabbix_baseurl}/slack_charts"
chart_basedir="/tmp/slack_charts"
chart_cookie="/tmp/zcookies.txt"

# s3 settings
s3_bucket="bucket-name"
s3_config_path="/path/to/config/.s3cfg"

# set params
host="`echo \"${params}\" | grep 'HOST: ' | awk -F'HOST: ' '{print $2}' | sed -e 's///g'`"
trigger_name="`echo \"${params}\" | grep 'TRIGGER_NAME: ' | awk -F'TRIGGER_NAME: ' '{print $2}' | sed -e 's///g'`"
trigger_status="`echo \"${params}\" | grep 'TRIGGER_STATUS: ' | awk -F'TRIGGER_STATUS: ' '{print $2}' | sed -e 's///g'`"
trigger_severity="`echo \"${params}\" | grep 'TRIGGER_SEVERITY: ' | awk -F'TRIGGER_SEVERITY: ' '{print $2}' | sed -e 's///g'`"
trigger_url="`echo \"${params}\" | grep 'TRIGGER_URL: ' | awk -F'TRIGGER_URL: ' '{print $2}' | sed -e 's///g'`"
datetime="`echo \"${params}\" | grep 'DATETIME: ' | awk -F'DATETIME: ' '{print $2}' | sed -e 's///g'`"
item_value="`echo \"${params}\" | grep 'ITEM_VALUE: ' | awk -F'ITEM_VALUE: ' '{print $2}' | sed -e 's///g'`"
event_id="`echo \"${params}\" | grep 'EVENT_ID: ' | awk -F'EVENT_ID: ' '{print $2}' | sed -e 's///g'`"
item_id="`echo \"${params}\" | grep 'ITEM_ID: ' | awk -F'ITEM_ID: ' '{print $2}' | sed -e 's///g'`"

# get charts
if [ "${item_id}" != "" ]; then
    timestamp=$(date +%s)

    ${cmd_wget} --save-cookies="${chart_cookie}_${timestamp}" --keep-session-cookies --post-data "name=${zabbix_username}&password=${zabbix_password}&enter=Sign+in" -O /dev/null -q "${zabbix_baseurl}/index.php?login=1"
    ${cmd_wget} --load-cookies="${chart_cookie}_${timestamp}"  -O "${chart_basedir}/graph-${item_id}-${timestamp}.png" -q "${zabbix_baseurl}/chart.php?&itemids=${item_id}&width=${chart_width}&period=${chart_period}"
		s3cmd -c ${s3_config_path} --acl-public put ${chart_basedir}/graph-${item_id}-${timestamp}.png s3:${s3_bucket}
    chart_url="http://${s3_bucket}/graph-${item_id}-${timestamp}.png"
    rm -f ${chart_cookie}_${timestamp}

    # if triger url is empty then we link to the graph with the item_id
    if [ "${trigger_url}" == "" ]; then
        trigger_url="${zabbix_baseurl}/history.php?action=showgraph&itemids=${item_id}"
    fi
fi

# set color
if [ "${trigger_status}" == 'OK' ]; then
  case "${trigger_severity}" in
    'Information')
      color="#439FE0"
      ;;
    *)
      color="good"
      ;;
  esac
elif [ "${trigger_status}" == 'PROBLEM' ]; then
  case "${trigger_severity}" in
    'Information')
      color="#439FE0"
      ;;
    'Warning')
      color="warning"
      ;;
    *)
      color="danger"
      ;;
  esac
else
  color="#808080"
fi

# set payload
payload="payload={
  \"channel\": \"${channel}\",
  \"username\": \"${slack_username}\",
  \"icon_emoji\": \"${emoji}\",
  \"attachments\": [
    {
      \"fallback\": \"Date / Time: ${datetime} - ${title}\",
      \"title\": \"${title}\",
      \"title_link\": \"${trigger_url}\",
      \"color\": \"${color}\",
      \"fields\": [
        {
            \"title\": \"Date / Time\",
            \"value\": \"${datetime}\",
            \"short\": true
        },
        {
            \"title\": \"Status\",
            \"value\": \"${trigger_status}\",
            \"short\": true
        },
        {
            \"title\": \"Host\",
            \"value\": \"${host}\",
            \"short\": true
        },
        {
            \"title\": \"Trigger\",
            \"value\": \"${trigger_name}: ${item_value}\",
            \"short\": true
        }
      ],
     \"image_url\": \"${chart_url}\"
    }
  ]
}"

# send to slack
${cmd_curl} -m ${timeout} --data-urlencode "${payload}" "${slack_url}"

