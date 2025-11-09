#!/bin/bash
# awsutillib.sh
# bash shell library for working with AWS EC2 instances via CLI
# source this file into your scripts to access these functions

# uncomment, or export env var, or set from cmd line to disable ssl verify
#auNoSSL="y"
[ "$auNoSSL" == "y" ] && auNOS="--no-verify-ssl" || auNOS=""

#--------------------------------------------------------------------------------
# print autag bash array of tags/values to stdout
# input: "raw" = print data only, or "" = human readable
# output: none
#         set env var auDBug="y" to output debug messages to console
#--------------------------------------------------------------------------------
auPrnTags() {
   I=0              # index to step thru list
   J=${#auTag[@]}  # number of tag/val elements in array
   K=$((J/2))       # number of tags
   L=1              # count line numbers

   [ "$auDBug" == "y" ] && echo "$auHdr: autag has $K tags."

   # step thru array, display each tag=val
   while [ $I -lt $J ]; do
      # raw mode = only the data, easily parsed by scripts
      if [ "$1" == "raw" ]; then
         echo "${auTag[I]}=${auTag[((I+1))]}"
      # human readable = add lines numbers and format aligned
      else
         printf "%02d: %17s = %s\n" $L "${auTag[1]}" "${auTag[((I+1))]}"
      fi
      ((I+=2)) # step to next tag/val pair in array
      ((L++))  # next line number
   done

} # auPrnTags

#--------------------------------------------------------------------------------
# fetch EC2 instance data
# input:  auIID = bash array of one or more instance ids, e.g. ("i-02678b1cb811d026b")
# output: return o = success, !0 = error
#         audat, string of ec2 json data
#         set env var audBug="y" to output debug messages to console
#--------------------------------------------------------------------------------
auGetInst() {
   auRC=0 # status, 0 = success, !0 = error

   # basename for output files
   auHdr="auGetInst"
   auRan="$RANDOM" auBas="/var/tmp/awsutilib-$auRan"
   auTmp="$auBas.tmp"

   # remember: to preserve spaces in args when expanding array, ref must be in ""

   # fetch instances into string (index array @ to preserve spaces in elements)
   auCmd="aws ec2 describe-instances $auNOS --instance-ids ${auIID[@]} --output json"
   [ "$auDBug" == "y" ] && echo "$auHdr: execute: $auCmd"
   auDat=$($auCmd)
   auRc=$?
   [ "$auDBug" == "y" ] && echo "$auHdr: rc=$auRC"

   # debug
   if [ "$auDBug" == "y" ]; then
       if [ $auRc -ne 0 ]; then 
           echo "$auHdr:Error: $auRC, Mesg: $auDat, Cd: $auCmd"
       else
           echo "$auHdr: Success, save command and output to $auBas.{cmd, json}"
           echo "$auCmd" > $auBas.cmd
           echo "$auDat" > $auBas.json
      fi
   fi

   return $auRC;
} # auGetInst

#--------------------------------------------------------------------------------
# parse tag/values from json string of ec2 data (as returned by augetInst)
# input: auDat, string of json instance data
# output: return 0 = success, !0 = error
#         auTag, array of tags/values, [0]=tag1, [1]=val1, etc.
#         set env var auDBug="y" to output debug messages to console
#--------------------------------------------------------------------------------
auParTags() {
    # basename for output files
    auHdr="auParTags"
    auRan="$RANDOM"
    auBas="/var/tmp/awsutilib-$auRan"
    auTmp="$auBas.tmp"

    # parse tags, step 1 create temp file of tags and values
    cp /dev/null $auTmp
    auCnt=0
    export IFS='='
    # cat i-02678b1cb811d026b.json | \ ## for dubgging
    echo "$auDat" | \
       jq '.Reservations[].Instances[].Tags[] | "\(.Key)=\(.Value)"' | tr -d | \
       while read -r A B; do
          echo -n "$A^$B^">> $auTmp
          ((auCnt++)) # local to pipeline
       done
    #[ "$auDBug" == "y" ] && echo "$audr: Parsed $auCnt tags." # auCnt was local to pipeline

    # parse tags, step 2 read temp file into bash array
    auStr=$(<$auTmp)
    export IFS='^'
    auTag=( $auStr )  # array of one string
    #[ "$auDBug" == "y" ] && auPrnTags

} # auParTags

#--------------------------------------------------------------------------------
# set tag/values for given instance id(s)
# input: aulID, array of instance id(s)
#        auTag, array of tags/values to set
# output: return 0 = success, !0 = error
#         set env var auDBug="y" to output debug messages to console
#--------------------------------------------------------------------------------
auSetTags() {
    # basename for output files
    auHdr="auSetTags"

    # format tags
    I=0               # index to step thru list
    J=${#auTag[@]}   # number of elements in array
    auTval=( )
    K=0
    while [ $I -lt $J ]; do
        T=${auTag[I]}; ((I++)); # tag
        V=${auTag[I]}; ((I++)); # value
        auTval[$K]="Key=$T,Value=$V"; ((K++))
    done

    # debug, dump auTval
    [ "$auDBug" == "y" ] && I=0; J=${#auTval[@]}; while [ $I -lt $J ]; do echo "1: ${auTval[$I]}"; done
    #echo "*** debug exit ***"; exit 1

    # fetch instances into string (index array @ to preserve spaces in elements)
    auCmd="aws ec2 create-tags $auNOS --resources ${auTID[@]} --tags ${auTval[@]} --output json"

    [ "$auDBug" == "y" ] && echo "$auHdr: execute: $auCmd"
    auDat=$($auCmd)
    auRC=$?
    [ "$auDBug" == "y" ] && echo "$auHdr: rc=$auRC"

    # format cmd
    export IFS='='
    # cat i-02678b1cb811d026b.json | \ ## for dubgging
    echo "$auDat" | \
        jq '.Reservations[].Instances[].Tags[] | "\(.Key)=\(.Value)"' | tr -d '"' | \
        while read -r A B; do
            echo -n "$A^$B^" >> $auTmp
            ((auCnt++)) # local to pipeline
        done
    [ "$auDBug" == "y" ] && echo "$auHdr: Parsed $auCnt tags." # auCnt local to pipeline

    # parse tags, step 2 read temp file into bash array
    auStr=$(<$auTmp)
    export IFS='^'
    auTag=( $auStr )
    #[ "$auDBug" == "y" ] && auPrnTags

} # auSetTags
#--------------------------------------------------------------------------------
