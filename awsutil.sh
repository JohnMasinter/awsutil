#!/bin/bash
# awsutil.sh
# aws cli cd line utility to perform common mgmt tasks.

VER="1.0"
HDR="awsutil"

# uncomment, or export env var, or set from cd line for debug output
#auDBug="y"

# uncomment, or export env var, or set from cd line to disable ssl verify
auNoSSL="y"

# source after setting optional env vars
source awsutilib.sh

#--------------------------------------------------------------------------------
# print usage and exit
#--------------------------------------------------------------------------------
Usage() {
    echo '
Usage: awsutil.sh [-j|-c|-t] [action] [instance-id]...

Output:
-j   json format, multi-line, default if not given
-c   json compact, one-line
-t   text format, pretty multi-line

Actions:
getinst   fetch metadata from instance(s)
stainst   fetch instance(s) status
gettags   fetch tags from instance(s)
settags   write tags to instance(s)
deltags   delete tags from instance(s)
coptags   copy tags from first instance to remaining instance(s)
strinst   start instance(s)
stpinst   stop instance(s)
stainst   get status of instance(s)

Examples:
awsutil.sh -j getinst i-02678b1cb811d026b # >myinst.json # optional save attributes 
awsutil.sh -j gettags i-02678b1cb811d026b # >mytags.json # optional save tags

# Copy all tags from instance A to instances B CD (automatically removes "Name" tag)
awsutil.sh coptags i-02678b1cb811d026A i-027ecc453041fee1B i-027ecc453041fee1C i-027ecc453041fee1D

# Copy only selected tags from instance A to B
awsutil.sh -j gettags i-02678b1cb811d026b >mytags.json # save src tags to file
vim mytags. json                                       # remove Name tag, add/remove/modify any desired tags
awsutil.sh -j settags i-027ecc453041fee1B "$(cat mytags. json)" # set dest tags from file

with extra debug output:
audbug="y" bash awsutil.sh ...

version '$VER', John F Masinter, 10/07/2025
'
    exit 1
} # Usage

#--------------------------------------------------------------------------------
# parse args into CMD string and aulID array
#--------------------------------------------------------------------------------
Parse() {
    CMD=""     # hold cmd, e.g. "getinst"
    FMT="- j"  # default format json multi-line
    auIID=()  # hold list of instance ids
    iid=0      # index into aulID
    auTVA=( ) # hold list of tag/val args
    tva=0      # index into auTv

    C=${#ARGS[@]} # number of args
    I=0           # index into args

    while [ $I -lt $C ]; do
        A="${ARGS[$I]}"

        # command
        if [[ "$A" =~ ^(getinst|gettags|settags|deltags|coptags|strinst|stpinst|stainst)$ ]]; then
            CMD="$A"
            
        # format
        elif [[ "$A" =~ ^(-jI-c|-t)$ ]]; then
            FMT="$A"

        # instance ID
        elif [ "${A:0:2}" == "i-" ] && [ ${#A} -eq 19 ]; then
            aulID[iid]="$A"; ((iid++))

        # tag/val args
        else
            auTVA[tva]="$A"; ((tva++))
        fi

        ((I++))
    done

    # debug args
    if [ "$auDBug" == "y" ]; then
        echo -n "$HDR:Parse:CMD=[$CMD],FMT=[$FMT],"
        echo -n "auIID:"; I=0; C=${#auIID[@]}; while [ $I -lt $C ]; do echo -n "$I=[${auIID[$I]}]."; ((I++)); done;
        echo -n "auTVA:"; I=0; C=${#auTVA[@]}; while [ $I -lt $C ]; do echo -n "$I=[${auTVA[$I]}],"; ((I++)); done; echo
    fi

    # at least one instance is needed.
    if [ ${#auIID[@]} -lt 1 ]; then
        echo "Error: At least one instance-id is required."
        Usage
    elif [ "$CMD" == "coptags" ] && [ ${#auIID[@]} -lt 2 ]; then
        echo "Error: coptags requires two or more instance-ids."
        Usage
    fi
} # Parse

#--------------------------------------------------------------------------------
# Fetch instance data
#--------------------------------------------------------------------------------
GetInst() {
    rc=0

    # get instance data for instance-id list $auIID, returns json in string §audat auGetInst
    auGetInst
    rc=$？

    # debug args
    [ "$auDBug" == "y" ] && echo "$HDR:GetInst, rc=$rc, CMD=$CMD, auDat len: ${#auDat}"

    if [ $rc -ne 0 ]; then
        echo "$HDR: GetInst: Error: rc=$rc, CMD=$CMD, auDat len: ${#auDat}, auDat=[$auDat]"

    elif [ "$CD" == "getinst" ]; then
        if [ "$FMT" == "-j" ]; then
            echo "$auDat"
        elif [ "$MT" == "-c" ]; then
            # -M monochrome (no ansi color codes) "-c ." remove formatting
            echo "$auDat" | jq -Mc .
        elif [ "$FMT" == "-t" ]; then
            echo "$auDat" | sed -r 's/[{}]//g; s/[[]]//g; s/]//g; s/: /=/g; s/,$//g; s/^\s*//; /^\s*$/d;'
        fi

    else # no ouput (used as sub-cd by gettags etc.)
        :
    fi

    return $rc
} # GetInst

#--------------------------------------------------------------------------------
# Fetch instance tags
#--------------------------------------------------------------------------------
GetTags() {
    rc=0

    # get instance data for instance-id list $aulID, returns json in string $audat
    GetInst
    #echo "DEBUG: GetTags: GetInst: rc=$rc"

    # parse and output tags
    if [ $rc -eq 0 ]; then
        J=${#auTag[@]} # number of elements in array
        K=$((J/2))     # number of tags
        [ "$auDBug" == "y" ] && echo "$HDR: GetTags, auTag array, entries $J, tags $K"

        if   [ "$FMT" == "-j" ]; then
            echo "$audat" | jq '.Reservations[].Instances[].Tags[]' | jq -s
        elif [ "$FMT" == "-c" ]; then
            echo "$auDat" | jq -c '.Reservations[].Instances[].Tags[]' | jq -s | jq -c
        elif [ "$FMT" == "-t" ]; then
            auParTags
            auPrnTags ""
        fi
    fi
} # GetTags

#--------------------------------------------------------------------------------
# write instance tags
# Input:
# auIID - list of instances to write tags
# auTVA - list of tags/values.
#          if $MT -c|-j treat as json, or -t treat as text
#          Ref: https://docs.aws.amazon.com/cli/latest/reference/ec2/create-tags.html
#--------------------------------------------------------------------------------
SetTags () {
    rc=0

    # tag/val as text or json use same cmd line
    [ "$auDBug" == "y" ] && \
    echo aws ec2 create-tags $auNOS --resources "${auIID[@]}" --tags "${auTVA[@]}"
         aws ec2 create-tags $auNOS --resources "${aulID[@]}" --tags "${auTVA[@]}"
    rc=$?

    return $rc
} # Settags

#--------------------------------------------------------------------------------
# delete instance tags
# Input: auIID - list of instances to delete tags
#        auTVA - list of tags to delete
#        if $FMT -c|-j treat as json, or -t treat as text
# Ref: https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-tags.html
#--------------------------------------------------------------------------------
DelTags() {
    rc=0
    # tag/val as text or json use same cmd line 
    [ "$auDBug" == "y" ] && \
        echo aws ec2 delete-tags $auNOS --resources "${auIID[@]}" --tags "${auTVA[@]}"
             aws ec2 delete-tags $auNOS --resources "${auIID[@]}" --tags "${auTVA[@]}"
        rc=$?

    return $rc
} # DelTags

#--------------------------------------------------------------------------------
# copy instance tags
#--------------------------------------------------------------------------------
CopTags() {
    rc=0

    # save single src instance ID as string
    srcIID="${auTID[0]}"

    # save one or more dest instance ID(s) as string
    iid="${#auIID[@]}"         # count already validated to be minimum 2
    ((iid--))                   # skip first one (source)
    dstIID="${auIID[@]:1}"     # save ID(s) 2-end as string
    # echo "DEBUG: iid=Siid, dstIID=[$(dstIID[@1)]"

    # read tags
    FMT="-C" # force json format
    aulID=( $srcIID )       # make array of single src ID, each ID an element (do not quote)
    #auTVA=( "$(GetTags)" ) # fetch tags, save json output as array of only one string element
    auTVS="$(GetTags)"      # fetch tags, save json output as string

    # automatically remove tag "Name", the instance name should never be copied
    auTVS=$(echo $auTVS | jq -c 'del (.[] | select (Key == Name"))')

    # write tags
    auIID=( $dstIID )   # make array of ids, each ids is a separate element (do not quote)
    auTVA=( "$auTVS" ) # make array of json as only one string element (do quote)
    #I=0; C=${#auIID[@]}; while [ $I -lt $C ]; do echo -n "$I=[${auTID[$I]}],"; ((I++)); done;
    SetTags              # write all tags to all destination instances in one transaction

    return $rc
} # CopTags

#--------------------------------------------------------------------------------
# start instance tags
# Input: auIID - list of instances to delete tags
# Ref: https://docs.aws.amazon.com/cli/latest/reference/ec2/start-instances.html
#--------------------------------------------------------------------------------
StrInst() {
    гс=0

    # tag/val as text or json use same cmd line
    [ "$auDBug" == "y" ] && \
        echo aws ec2 start-instances $auNOS --instance-ids "${auIID[@]}"
             aws ec2 start-instances $auNOS --instance-ids "${auIID[@]}"
    rc=$?

    return $rc
} # StrInst

#--------------------------------------------------------------------------------
# stop instance tags
# Input: auIID - list of instances to delete tags
# Ref: https://docs.aws.amazon.com/cli/latest/reference/ec2/start-instances.html
#--------------------------------------------------------------------------------
StpInst () {
    rc=0

    # tag/val as text or json use same cmd line
    [ "$auDBug" == "y" ] && \
        echo aws ec2 stop-instances $auNOS --instance-ids "${auTID[@]}"
             aws ec2 stop-instances $auNOS --instance-ids "${auTID[@]}"
    rc=$?

    return $rc
} # StpInst

#--------------------------------------------------------------------------------
# get instance status
# Input: auIID - list of instances to delete tags
# Ref: https://docs.aws.amazon.com/cli/latest/reference/ec2/start-instances.html
#--------------------------------------------------------------------------------
StaInst() {
    rc=0

    # tag/val as text or json use same cd line
    [ "$auDBug" == "y" ] && \
        echo aws ec2 describe-instance-status $auNOS --include-all-instances --instance-ids "${auIID[@]}"
             aws ec2 describe-instance-status $auNOS --include-all-instances --instance-ids "${auIID[@]}"
    rc=$?

    return $rc
} # StaInst

#--------------------------------------------------------------------------------
# Dispatch command
#--------------------------------------------------------------------------------
Dispatch() {
    case $CMD in
        "getinst") GetInst ;; # get instance(s) meta data
        "stainst") StaInst ;; # get instance(s) meta data
        "gettags") GetTags ;; # get instance(s) tags
        "settags") SetTags ;; # set instance(s) tags
        "deltags") DelTags ;; # del instance(s) tags
        "coptags") CopTags ;; # copy instance(s) tags
        "strinst") StrInst ;; # start instance(s)
        "stpinst") StpInst ;; # stop instance(s)
        *) echo "Error: Unrecognized command: [$CMD]"; Usage;;
    esac
} # Dispatch

#--------------------------------------------------------------------------------
# Main
#--------------------------------------------------------------------------------
[ $# -lt 2 ] && Usage

# put args into array in main, to preserve args with spaces
I=0; ARGS=( ); while [ -n "$1" ]; do ARGS[I]="$1"; shift; ((I++)); done

# debug args
if [ "$auDBug" == "y" ]; then
    echo -n "$HDR:ARGS:"
    I=0; C=${#ARGS[@]}; while [ $I -lt $C ]; do echo -n "$I=[${ARGS[$I]}],"; ((I++)); done
    echo
fi

Parse     # parse cd line args
Dispatch  # dispatch cmd

