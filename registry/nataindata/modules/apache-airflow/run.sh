#!/usr/bin/env sh

BOLD='\033[0;1m'

PATH=$PATH:~/.local/bin
pip install --upgrade apache-airflow

filename=~/airflow/airflow.db
if ! [ -f $filename ] || ! [ -s $filename ]; then
  airflow db init
fi

export AIRFLOW__CORE__LOAD_EXAMPLES=false

airflow webserver > ${LOG_PATH} 2>&1 &

airflow scheduler >> /tmp/airflow_scheduler.log 2>&1 &

airflow users create -u admin -p admin -r Admin -e admin@admin.com -f Coder -l User
