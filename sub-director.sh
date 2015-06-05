#!/bin/sh
# Author:  Matthew Davis <amd@redhat.com>
# Date:    5 Jun 2015
# Version: 0.2
# License: GPLv2
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Disclaimer: I am not a programmer by trade. And this script should be
#             sufficient evidence, that because I know how to script
#             does not mean I should.
#
# Purpose: To make registering a RHEL host with subscription-manager easier
#          
# Usage: ./sub-director.sh
#        - it should prompt for all input
#
# Changelog
# - v0.1 - initial release
#   v0.2 - fix reg w/o satellite & paths on rhel6
#
# TODO: * account for providing incorrect user/pass
#       * If a subscription name is entirely contained within another sub
#         name, allow for the search to accomodate it. For example
#         - Red Hat Satellite & Red Hat Satellite Capsule Server
#         no way to selct just the Red Hat Satellite sub
#       * maybe provide some way to show details of a sub if requested
#       * line 179: [: -eq: unary operator expected, which is the first if
#         in find_sub
#

SUBMGR=/usr/sbin/subscription-manager
RPMBIN=/bin/rpm
GREPBIN=/bin/grep


read_yn() {
  echo -n "(y/N) "
  read RESPONSE
}

check_environment() {
  # rpm check
  $RPMBIN -q subscription-manager > /dev/null
  if [ $? -ne 0 ]; then
    # exit if sub-mgr is not installed
    echo "subscription-manager RPM is not found"
    exit 1
  fi
  # check exeuction user
  if [ $USER != 'root' ]; then
    echo "Command must be run by root"
    exit 2
  fi
  # check if we're talking to a satellite or not
  # maybe not the cleanest test, but it works for now
  $RPMBIN -qa | $GREPBIN katello-ca-consumer > /dev/null
  SATELLITE=$?
  # TODO: maybe specific version of sub-mgr?
  #       network communcation, but shuldnt sub-mgr error on that?
}

disclaimer() {
  echo "NOTICE: By using this script, you promise to not contact support for help"
  echo "        with this script. Support will only help with direct execution of"
  echo "        'subscription-manager' and associated commands"
  echo ""
  echo "Do you agree?"
  read_yn
  if [[ $RESPONSE =~ ^(yes|ye|y)$ ]]; then
    echo "Thank-you"
  else
    echo "Don't do this. They deserve better. They deal with enough already"
    echo "Will you reconsider?"
    read_yn
    if [[ $RESPONSE =~ ^(yes|ye|y)$ ]]; then
      echo "Thank-you"
    else
      echo "Sigh. You leave me no choice. Formatting the drive"
      echo 'C:> format c:'
    fi
  fi
}

get_registered_state() {
  # echo because you can be registered and not attached to a sub, lets handle each one
  # states of SUBSTATE
  # 0 = host already registered with subscriptions attached
  # 1 = host not registered
  # 2 = host registered but no subscriptions attached
  SUBMGRSTATUS=$($SUBMGR status)
  if echo $SUBMGRSTATUS | $GREPBIN Unknown > /dev/null; then
    SUBSTATE=1
  fi
  if echo $SUBMGRSTATUS | $GREPBIN Invalid > /dev/null; then
    SUBSTATE=2
  fi
  if echo $SUBMGRSTATUS | $GREPBIN Current > /dev/null; then
    SUBSTATE=0
  fi
}

capture_login() {
  # TODO Clenaup input
  echo -n "Username: "
  read SUBMGRUSR
  echo -n "Password: "
  read -s SUBMGRPW
  echo -e "\nThanks"
}

register_host() {
  if [ $SATELLITE -eq "0" ]; then
    # satellites expect an environment and Library is the default one
    $SUBMGR register --username $SUBMGRUSR --password $SUBMGRPW --environment=Library
  else
    $SUBMGR register --username $SUBMGRUSR --password $SUBMGRPW
  fi
  attach_subs
}

auto_attach() {
  echo Executing $SUBMGR attach --auto
  $SUBMGR attach --auto
}

attach_subs() {
  echo Do you want me to try auto attaching subs? Normally this does the 'Right Thing(tm)'
  read_yn
  if [[ $RESPONSE =~ ^(yes|ye|y)$ ]]; then
    auto_attach
  else
    echo Do you want to pick a subscription from a list of subscriptions
    read_yn
    if [[ $RESPONSE =~ ^(yes|ye|y)$ ]]; then
      find_sub
  #    SUBSCRIPTIONS=$($SUBMGR list --all --available)
  #    SUBNAMES=($(echo "$SUBSCRIPTIONS" | grep "Subscription Name" | awk -F"   " '{print $2}' | sort|uniq))
  #    echo ${#SUBNAMES[@]}
    fi
  fi
}
  

register_machine() {
  if [ $SUBSTATE -eq 0 ]; then
    echo Host already registered
  fi
  if [ $SUBSTATE -eq 1 ]; then
    echo Not registered would you like to regsiter?
    read_yn
    if [[ $RESPONSE =~ ^(yes|ye|y)$ ]]; then
      capture_login
      register_host
    fi
  fi
  if [ $SUBSTATE -eq 2 ]; then
    attach_subs
  fi
}

search_subs() {
  echo "$SUBLIST" | $GREPBIN -i $SEARCH | wc -l
}

find_poolid() {
  echo "$SUBS" | sed "/Subscription Name:  .*$1*./I,\$!d" | $GREPBIN Pool | head -1 | awk -F":" '{print $2}' |  sed -e 's/^[ \t]*//'
}

find_sub() {
  # this is a recursive function
  if [ $NUMINLIST -eq "1" ]; then
    POOLID=$(find_poolid $SEARCH)
    echo Running subscription-manager attach --pool=$POOLID
    $SUBMGR attach --pool=$POOLID
  else
    SUBS=$($SUBMGR list --all --available)
    #SUBSCRIPTIONS=$(cat blah)
    #SUBS=($(echo "$SUBSCRIPTIONS" | grep "Subscription Name" | awk -F"   " '{print $2}' | sort | uniq))
    #echo $SUBS

#    SUBS=$(cat blah)
    # show subscriptions
    if [ -z $SEARCH ]; then
      SUBLIST=$(echo "$SUBS" | $GREPBIN "Subscription Name" | awk -F"   " '{print $2}' | sort|uniq)
    else
      SUBLIST=$(echo "$SUBS" | grep "Subscription Name" | awk -F"   " '{print $2}' | sort|uniq | grep -i $SEARCH)
    fi
    echo -e "\n\n-- Subscription List --\n"
    echo "$SUBLIST"
    echo -e "\nPlease provide enough of a description (case-insenstive) of the subscription you would like to attach"
    read SEARCH
    NUMINLIST=$(search_subs)
    # this is a recursive function
    find_sub
  fi
}


disclaimer
check_environment
get_registered_state
register_machine
