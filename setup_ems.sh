#!/bin/bash
#create vheads.sh, Andrew Renz, Sept 2017, June 2018
#Script to configure Elastifile EManage (EMS) Server, and deploy cluster of ECFS virtual controllers (vheads) in Google Compute Platform (GCE)
#Requires terraform to determine EMS address and name (Set EMS_ADDRESS and EMS_NAME to use standalone)

set -ux

#impliment command-line options
#imported from EMS /elastifile/emanage/deployment/cloud/add_hosts_google.sh

# function code from https://gist.github.com/cjus/1047794 by itstayyab
function jsonValue() {
 KEY=$1
 awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$KEY'\042/){print $(i+1)}}}' | tr -d '"'| tr '\n' ','
}


usage() {
  cat << E_O_F
Usage:
  -c configuration type: "small" "medium" "large" "standard" "small standard" "local" "small local" "custom"
  -l load balancer: "none" "dns" "elastifile" "google"
  -t disk type: "persistent" "hdd" "local"
  -d disk config: eg 8_375
  -v vm config: eg 4_42
  -p IP address
  -r cluster name
  -s deployment type: "single" "dual" "multizone"
  -a availability zones
  -e company name
  -f contact person
  -g contact person email
  -i clear tier
  -k async dr
  -j lb vip
E_O_F
  exit 1
}

#variables
SESSION_FILE=session.txt
PASSWORD=`cat password.txt | cut -d " " -f 1`
DISKTYPE=local
LOG="setup_ems.log"

while getopts "h?:c:l:t:d:v:p:s:a:e:f:g:i:k:j:r:" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    c)  CONFIGTYPE=${OPTARG}
        [ "${CONFIGTYPE}" = "small" -o "${CONFIGTYPE}" = "medium" -o "${CONFIGTYPE}" = "large" -o "${CONFIGTYPE}" = "standard" -o "${CONFIGTYPE}" = "small standard" -o "${CONFIGTYPE}" = "local" -o "${CONFIGTYPE}" = "small local" -o "${CONFIGTYPE}" = "custom" ] || usage
        ;;
    l)  LB=${OPTARG}
        ;;
    t)  DISKTYPE=${OPTARG}
        [ "${DISKTYPE}" = "persistent" -o "${DISKTYPE}" = "hdd" -o "${DISKTYPE}" = "local" ] || usage
        ;;
    d)  DISK_CONFIG=${OPTARG}
        ;;
    v)  VM_CONFIG=${OPTARG}
        ;;
    p)  EMS_ADDRESS=${OPTARG}
        ;;
    s)  DEPLOYMENT_TYPE=${OPTARG}
        ;;
    a)  AVAILABILITY_ZONES=${OPTARG}
        ;;
    e)  COMPANY_NAME=${OPTARG}
        ;;
    f)  CONTACT_PERSON_NAME=${OPTARG}
        ;;
    g)  EMAIL_ADDRESS=${OPTARG}
        ;;
    i)  ILM=${OPTARG}
        ;;
    k)  ASYNC_DR=${OPTARG}
        ;;
    j)  LB_VIP=${OPTARG}
	      ;;
    r)  EMS_NAME=${OPTARG}
        ;;
    esac
done

#capture computed variables

# load balancer mode
if [[ $LB == "elastifile" ]]; then
  USE_LB="true"
elif [[ $LB == "dns" ]]; then
  USE_LB="false"
else
  USE_LB="false"
fi

#deployment mode
if [[ $DEPLOYMENT_TYPE == "single" ]]; then
  REPLICATION="1"
elif [[ $DEPLOYMENT_TYPE == "dual" ]]; then
  REPLICATION="2"
else
  REPLICATION="2"
fi

echo "EMS_ADDRESS: $EMS_ADDRESS" | tee ${LOG}
echo "EMS_NAME: $EMS_NAME" | tee -a ${LOG}
echo "DISKTYPE: $DISKTYPE" | tee -a ${LOG}
echo "LB: $LB" | tee -a ${LOG}
echo "USE_LB: $USE_LB" | tee -a ${LOG}
echo "DEPLOYMENT_TYPE: $DEPLOYMENT_TYPE" | tee -a ${LOG}
echo "REPLICATION: $REPLICATION" | tee -a ${LOG}
echo "COMPANY_NAME: $COMPANY_NAME" | tee -a ${LOG}
echo "CONTACT_PERSON_NAME: $CONTACT_PERSON_NAME" | tee -a ${LOG}
echo "EMAIL_ADDRESS: $EMAIL_ADDRESS" | tee -a ${LOG}
echo "ILM: $ILM" | tee -a ${LOG}
echo "ASYNC_DR: $ASYNC_DR" | tee -a ${LOG}
echo "LB_VIP: $LB_VIP" | tee -a ${LOG}

#set -x

#establish https session
function establish_session {
  echo -e "Establishing https session..\n" | tee -a ${LOG}
  curl -k -D ${SESSION_FILE} -H "Content-Type: application/json" -X POST -d '{"user": {"login":"admin","password":"'$1'"}}' https://$EMS_ADDRESS/api/sessions >> ${LOG} 2>&1
}

function first_run {
  #loop function to wait for EMS to complete loading after instance creation
  while true; do
    emsresponse=`curl -k -s -D ${SESSION_FILE} -H "Content-Type: application/json" -X POST -d '{"user": {"login":"admin","password":"changeme"}}' https://$EMS_ADDRESS/api/sessions | grep created_at | cut -d , -f 8 | cut -d \" -f 2`
    echo -e "Waiting for EMS init...\n" | tee -a ${LOG}
    if [[ $emsresponse == "created_at" ]]; then
      sleep 30
      echo -e "EMS now ready!\n" | tee -a ${LOG}
      break
    fi
    sleep 10
  done
}

# Configure ECFS storage type
# "small" "medium" "large" "standard" "small standard" "local" "small local" "custom"
function set_storage_type {
  echo -e "Configure systems...\n" | tee -a ${LOG}
  if [[ $1 == "small" ]]; then
    echo -e "Setting storage type $1..." | tee -a ${LOG}
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":'$USE_LB',"cloud_configuration_id":4}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
  elif [[ $1 == "medium" ]]; then
    echo -e "Setting storage type $1..." | tee -a ${LOG}
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":'$USE_LB',"cloud_configuration_id":5}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
  elif [[ $1 == "large" ]]; then
    echo -e "Setting storage type $1..." | tee -a ${LOG}
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":'$USE_LB',"cloud_configuration_id":6}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
  elif [[ $1 == "standard" ]]; then
    echo -e "Setting storage type $1..." | tee -a ${LOG}
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":'$USE_LB',"cloud_configuration_id":7}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
  elif [[ $1 == "small standard" ]]; then
    echo -e "Setting storage type $1..." | tee -a ${LOG}
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":'$USE_LB',"cloud_configuration_id":1}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
  elif [[ $1 == "local" ]]; then
    echo -e "Setting storage type $1..." | tee -a ${LOG}
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":'$USE_LB',"cloud_configuration_id":2}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
  elif [[ $1 == "small local" ]]; then
    echo -e "Setting storage type $1..." | tee -a ${LOG}
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":'$USE_LB',"cloud_configuration_id":3}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
  fi
}

function set_storage_type_custom {
    type=$1
    disks=`echo $2 | cut -d "_" -f 1`
    disk_size=`echo $2 | cut -d "_" -f 2`
    cpu_cores=`echo $3 | cut -d "_" -f 1`
    ram=`echo $3 | cut -d "_" -f 2`
    echo -e "Configure systems...\n" | tee -a ${LOG}
    echo -e "Setting custom storage type: $type, num of disks: $disks, disk size=$disk_size cpu cores: $cpu_cores, ram: $ram \n" | tee -a ${LOG}
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X POST -d '{"name":"legacy","storage_type":"'$type'","num_of_disks":'$disks',"disk_size":'$disk_size',"instance_type":"custom","cores":'$cpu_cores',"memory":'$ram',"min_num_of_instances":0}' https://$EMS_ADDRESS/api/cloud_configurations >> ${LOG} 2>&1
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":'$USE_LB',"cloud_configuration_id":9}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
}

function setup_ems {
  #accept EULA
  echo -e "\nAccepting EULA.. \n" | tee -a ${LOG}
  curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X POST -d '{"id":1}' https://$EMS_ADDRESS/api/systems/1/accept_eula >> ${LOG} 2>&1

  #configure EMS
  echo -e "Configure EMS...\n" | tee -a ${LOG}

  echo -e "\nGet cloud provider id 1\n" | tee -a ${LOG}
  curl -k -s -b ${SESSION_FILE} --request GET --url "https://$EMS_ADDRESS/api/cloud_providers/1" >> ${LOG} 2>&1

  echo -e "\nValidate project configuration\n" | tee -a ${LOG}
  curl -k -s -b ${SESSION_FILE} --request GET --url "https://$EMS_ADDRESS/api/cloud_providers/1/validate" >> ${LOG} 2>&1

  echo -e "Configure systems...\n" | tee -a ${LOG}
  curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"name":"'$EMS_NAME'","replication_level":'$REPLICATION',"show_wizard":false,"name_server":"'$EMS_NAME'.local","eula":true,"registration_info":{"company_name":"'$COMPANY_NAME'","contact_person_name":"'$CONTACT_PERSON_NAME'","email_address":"'$EMAIL_ADDRESS'","receive_marketing_updates":false}}' https://$EMS_ADDRESS/api/systems/1 >> ${LOG} 2>&1

  if [[ ${CONFIGTYPE} == "custom" ]]; then
    echo -e "Set storage type custom $DISKTYPE $DISK_CONFIG $VM_CONFIG \n" | tee -a ${LOG}
    set_storage_type_custom ${DISKTYPE} ${DISK_CONFIG} ${VM_CONFIG}
  else
    echo -e "Set storage type ${CONFIGTYPE} \n" | tee -a ${LOG}
    set_storage_type ${CONFIGTYPE}
  fi

  if [[ ${DEPLOYMENT_TYPE} == "multizone" ]]; then
    echo -e "Multi Zone.\n" | tee -a ${LOG}
    echo -e "Multi Zone.\n"
    all_zones=$(curl -k -s -b ${SESSION_FILE} --request GET --url "https://"${EMS_ADDRESS}"/api/availability_zones" | jsonValue name | sed s'/[,]$//')
    echo -e "$all_zones"
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"availability_zone_use":true}' https://${EMS_ADDRESS}/api/cloud_providers/1 >> ${LOG} 2>&1
    let i=1
    for zone in ${all_zones//,/ }; do
      zone_exists=`echo $AVAILABILITY_ZONES | grep $zone`
      if [[ ${zone_exists} == "" ]]; then
        curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"enable":false}' https://${EMS_ADDRESS}/api/availability_zones/$i >> ${LOG} 2>&1
      fi
      let i++
    done
  else
    echo -e "Single Zone.\n" | tee -a ${LOG}
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"availability_zone_use":false}' https://${EMS_ADDRESS}/api/cloud_providers/1 >> ${LOG} 2>&1
  fi

  if [[ ${USE_LB} = true && ${LB_VIP} != "auto" ]]; then
    echo -e "\n LB_VIP "${LB_VIP}" \n" | tee -a ${LOG}
    echo -e "\n LB_VIP "${LB_VIP}" \n"
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"load_balancer_vip":"'${LB_VIP}'"}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
  else
    LB_VIP=$(curl -k -s -b ${SESSION_FILE} --request GET --url "https://"${EMS_ADDRESS}"/api/cloud_providers/1/lb_vip"  | jsonValue vip | sed s'/[,]$//')
    echo -e "\n LB_VIP "${LB_VIP}" \n" | tee -a ${LOG}
    echo -e "\n LB_VIP "${LB_VIP}" \n"
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"load_balancer_vip":"'${LB_VIP}'"}' https://$EMS_ADDRESS/api/cloud_providers/1 >> ${LOG} 2>&1
  fi

}

function change_password {
  if [[ "x$PASSWORD" != "x" ]]; then
    echo -e "Updating password...\n" | tee -a ${LOG}
    #update ems password
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X PUT -d '{"user":{"id":1,"login":"admin","first_name":"Super","email":"admin@example.com","current_password":"changeme","password":"'$PASSWORD'","password_confirmation":"'$PASSWORD'"}}' https://$EMS_ADDRESS/api/users/1 >> ${LOG} 2>&1
    echo -e  "Establish new https session using updated PASSWORD...\n" | tee -a ${LOG}
    establish_session $PASSWORD
  fi
}

# ilm
function enable_clear_tier {
  if [[ $ILM == "true" ]]; then
    echo -e "auto configuraing clear tier\n"
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X POST  https://$EMS_ADDRESS/api/cc_services/auto_setup
  fi
}

# asyncdr
function enable_async_dr {
  if [[ $ASYNC_DR == "true" ]]; then
    echo -e "auto configuraing async dr\n"
    curl -k -b ${SESSION_FILE} -H "Content-Type: application/json" -X POST -d '{"instances":2,"auto_start":true}' https://$EMS_ADDRESS/api/hosts/create_replication_agent_instance
  fi
}
# Main
first_run
setup_ems
enable_clear_tier
change_password
enable_async_dr
