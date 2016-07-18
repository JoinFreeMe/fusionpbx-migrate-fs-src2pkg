#!/bin/bash

#Define global variables
fs_path="/usr/local/freeswitch"
fs_pkg_conf_dir="/etc/freeswitch"
fpbx_path="/var/www/fusionpbx"
fpbx_src_path="/usr/src/fusionpbx-install.sh/debian/resources/switch/"
#TO-DO:  Read the db credentials (username & password) from /var/www/fusionpbx/resources/config.php and set it to a variable
# Gonna use function getdb() to accomplish this and the results will be used to accomplish line #91

# Functions
main ()
{
  clear
  echo "${LICENSE}"

  read -p "Shall we proceed? [Y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    detect_os
    switch_check

    #First we stop the FreeSWITCH service
    echo "Stopping FreeSWITCH..."
    systemctl stop freeswitch

    #Next we rename existing directories which will prevent the package install
    #We first check if they exist then rename them
    #If they don't exist, then just rename and move on
    echo "Renaming ${fs_pkg_conf_dir} (if it exists) to ${fs_pkg_conf_dir}""_old"
    if [ -d "${fs_pkg_conf_dir}" ] 
      then mv "${fs_pkg_conf_dir}" "${fs_pkg_conf_dir}"\_old
    fi

    echo "Renaming ${fs_path} to ${fs_path}""_old" 
    mv "${fs_path}" "${fs_path}"\_old

    echo "Checking for the FusionPBX install folder"
    if [ -d "${fpbx_src_path}" ] 
      then
      echo "FusionPBX install folder found at ${fpbx_src_path}, switching to it."
      cd ${fpbx_src_path}
      cd /usr/src
      else
        echo "FusionPBX install folder was not found, so let's get it."
        cd /usr/src
        git clone https://github.com/fusionpbx/fusionpbx-install.sh.git
        chmod 755 -R /usr/src/fusionpbx-install.sh
        cd /usr/src/fusionpbx-install.sh/debian/resources/switch/
      fi
    fi

    echo "Ready to install FreeSWITCH"
    sleep 2
    echo "Please make a selection: [1] Official Release [2], Official Release with ALL MODULES, or [3] Master Branch"
    read answer
    if [[ ${answer} == 1 ]] 
      then ./package-release.sh

    elif [[ ${answer} == 2 ]]; 
      then ./package-all.sh

    elif [[ ${answer} == 3 ]]; 
      then ./package-master-all.sh
    fi

    # TO-DO:  
    # 1.  Check PostgreSQL db for the existence of the v_default_settings tables.  If it exists;
    # 2.  Count how many records exist where (default_setting_category = switch) - should be 17
    # 3.  Iterate through each record and verify that they are set correctly (as follows):
    #       COLUMNS --> default_setting_subcategory   default_setting_name    default_setting_value                 default_setting_enabled
    #                   base                          dir                     /usr                                  true
    #                   bin                           dir                     null                                  true
    #                   call_center                   dir                     /etc/freeswitch/autoload_configs      false
    #                   conf                          dir                     /etc/freeswitch                       true
    #                   db                            dir                     /var/lib/freeswitch/db                true
    #                   diaplan                       dir                     /etc/freeswitch/dialplan              false
    #                   extensions                    dir                     /etc/freeswitch/directory             false
    #                   grammar                       dir                     /usr/share/freeswitch/grammar         true
    #                   log                           dir                     /var/log/freeswitch                   true
    #                   mod                           dir                     /usr/lib/freeswitch/mod               true
    #                   phrases                       dir                     /etc/freeswitch/lang                  false
    #                   recordings                    dir                     /var/lib/freeswitch/recordings        true
    #                   scripts                       dir                     /usr/share/freeswitch/scripts         true
    #                   sip_profiles                  dir                     /etc/freeswitch/sip_profiles          false
    #                   sounds                        dir                     /usr/share/freeswitch/sounds          true
    #                   storage                       dir                     /var/lib/freeswitch/storage           true
    #                   voicemail                     dir                     /var/lib/freeswitch/storage/voicemail true
    # 4.  If the above three db checks pass, then we can assume the user has successfully updated the switch paths in Default Settings
    #     We should now be able to proceed with the next steps 3(e).


  # Step 4(e)(a)
  echo "Deleting switch configs pulled down by the package install from /etc/freeswitch ..."
  rm -rf /etc/freeswitch/*
  echo "Done"

  # Step 4(e)(b)
  echo "Restoring switch configs from /usr/local/freeswitch_old/* to /etc/freeswitch ..."
  cp -ar /usr/local/freeswitch_old/conf/* /etc/freeswitch
  echo "Done"

  # Step 4(e)(c)
  echo "Patching the lua.conf.xml file so it points to the new scripts directory ..."
  sed -i 's~base_dir}/scripts~script_dir}~' /etc/freeswitch/autoload_configs/lua.conf.xml

  # Step 4(f)
  # Let's fix permissions and restart the various services.
  cd "${fpbx_src_path}"
  ./package-permissions.sh
  systemctl daemon-reload
  systemctl try-restart freeswitch
  systemctl daemon-reload
  systemctl restart php5-fpm
  systemctl restart nginx


}

detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    # some systems dont have lsb-release yet have the lsb_release binary and
    # vice-versa
    if [ -e /etc/lsb-release ]; then
      . /etc/lsb-release

      if [ "${ID}" = "raspbian" ]; then
        os=${ID}
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      else
        os=${DISTRIB_ID}
        dist=${DISTRIB_CODENAME}

        if [ -z "${dist}" ]; then
          dist=${DISTRIB_RELEASE}
        fi
      fi

    elif [ `which lsb_release 2>/dev/null` ]; then
      dist=`lsb_release -c | cut -f2`
      os=`lsb_release -i | cut -f2 | awk '{ print tolower($1) }'`

    elif [ -e /etc/debian_version ]; then
      # some Debians have jessie/sid in their /etc/debian_version
      # while others have '6.0.7'
      os=`cat /etc/issue | head -1 | awk '{ print tolower($1) }'`
      if grep -q '/' /etc/debian_version; then
        dist=`cut --delimiter='/' -f1 /etc/debian_version`
      else
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      fi

    else
      unknown_os
    fi
  fi

  if [ -z "${dist}" ]; then
    unknown_os
  fi

  # remove whitespace from OS and dist name
  os="${os// /}"
  dist="${dist// /}"

  echo "Detected operating system as ${os}/${dist}."
  echo ""
}

unknown_os ()
{
  echo "Unfortunately, your operating system distribution and version are not supported by this script."
  echo "Please consider using the manual approach, if you know what you're doing!"
  echo ""
  echo "Exiting...."
  echo ""
  sleep 5
}

switch_check ()
{
echo "Checking for the existence of FreeSWITCH..."
  if [ -d "${fs_path}" ]
    then
      echo "Excellent!  The FreeSWITCH directory (${fs_path}) was found so let's continue."
      echo ""
    else
      echo "Error: Directory ${fs_path} does not exists."
      echo ""
      echo "The traditional FreeSWITCH path (${fs_path}) was not detected, as such, this script will stop execution."
      echo ""
      sleep 3
      exit 1
  fi
}

getdb()
{
  # Check the two locations where the FusionPBX config file could be, and extract the database credentials
  # which we will use to build our connection string
  if [[ -f "/etc/fusionpbx/config.lua" ]]; then 
    echo "Retrieving database info from /etc/fusionpbx/config.lua to build the connection string..."
    dbconn=$(sed -rn 's/database\.system\s*=\s*"(.*)";/\1/p' /etc/fusionpbx/config.lua)
  elif [[ -f "/usr/local/freeswitch/scripts/resources/config.lua" ]]; then
    echo "Retrieving database info from /usr/local/freeswitch/scripts/resources/config.lua to build the connection string..."
    dbconn=$(sed -rn 's/database\.system\s*=\s*"(.*)";/\1/p' /usr/local/freeswitch/scripts/resources/config.lua)
  fi
}

LICENSE=$( cat << DELIM
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# "THE UAYOR LICENSE" (Version 1)
#
# This is the Use At Your Own Risk (UAYOR) License.
# I, Kismet Agbasi, wrote this script.  As long as you retain this notice you can do whatever you want with it. This
# script is just my basic attempt to help automate the process of switching FreeSWITCH from source to packages on an
# existing and fully operational FusionBPX server.  I am by no means an expert and this script is not intended to be
# super advanced in anyway.
#
# If you appreciate the rudimentary work and feel you can contribute to making it better in anyway, please consider
# contributing some code via my Github repo.
#
# Author:
#   Kismet Agbasi <kagbasi@digitainc.com>
#
# Contributor(s):
#   <could you some - email me if you're interested>
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# SOME THINGS TO NOTE BEFORE WE PROCEED:
#
# This script will automatically check your system to ensure it is supported and that a source installation
# of FreeSWITCH actually exists.  The traditional path ($fs_path) is used for this check.
# Additionally, there are some files we will need from the FusionPBX installation folders, so if you don't have
# them this script will fetch them for you and place them in ($fpbx_path).
#
# NOTE:  If the FreeSWITCH path is not detected this script will not continue!!!
#
# VERY IMPORTANT:  IF YOU HAVE NOT BACKED UP YOUR SYSTEM, DO SO NOW!!!
#
# I take no responsibility for a failed system as a result of using this script.  If anything should go wrong
# a proper backup should be easy to restore.  If you proceed without taking a backup, YOU ARE FULLY RESPONSIBLE!!!
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
DELIM
)

# BEGIN SCRIPT EXECUTION
getdb
main
echo "Done!"
echo
exit 1