# @(#) Version 2024.07.31
#
# When calling this program you have the option to pass the parms of
# LAST This will query the BRMS database for the last save job that has run. Example chkbkubrm.sh LAST
# Specific job information. Example chkbkubrm.sh 123456/USER/WEEKLY
# CTLG + Name of BRMS control group and that save will run now. Example chkbkubrm.sh CTLG WEEKLY

# IFS working directory. Location of script and associated files
ifsdir='/scripts/chkbkubrm'
cd $ifsdir
# Setting path
export PATH=/QOpenSys/usr/bin:/usr/bin

# Vars
tempdir=$ifsdir/temp
archivedir=$ifsdir/archive
outputdir=$ifsdir/output
log=$tempdir/chkbkubrm.log                #Main log file for this job
out=$tempdir/chkbkubrm.out                #Used to capture the job information
job=''                           #Auto generated later. Adds single quotes around jobuc for SQL statements
jobuc=''                         #Upper case job information used in SQL statements
joblc=''                         #Lower case job information used in qsh statements
splnum=''                        #Auto generated lower in the script. Finds the Spool File Number for jobuc
file1=$outputdir/fulljoblog.txt             #Spool file with junk removed from it
file2=$tempdir/dsjoblog.txt               #Spool file with junk removed and blank spaces added before each MSGID
joblog=$outputdir/joblog.txt                #Job Log results
joblogtmp=$tempdir/joblog.tmp             #Temp file
archivejoblog=$archivedir/archivejoblog.txt  #Historical archive Job Log
hstlog=$outputdir/hstlog.txt                #History Log results
hstlogtmp=$tempdir/hstlog.tmp             #Temp file
archivehstlog=$archivedir/archivehstlog.txt  #Historical archive History Log
brmlog=$outputdir/brmlog.txt                #Display BRM LOG results
brmlogtmp=$tempdir/brmlog.tmp             #Temp file
archivebrmlog=$archivedir/archivebrmlog.txt  #Historical archive BRMS Log
msgidtmp=$tempdir/msgidtmp.tmp            #Temp list of all MSGIDs found in job log
msgidlist=$outputdir/msgidlist.txt          #List of all MSGIDs found in joblog

# Special Vars 
emaillist="('ryan.cooper@siriuscom.com')"
#emaillist="('email.address1@example.com') ('email.address2@example.com')"  #Example of multiple email address format
numdays='1'                                                                 #Number of days to search logs for job. Greater the number the more expensive the SQL queries.
omitjoblog="CPF0000"                                                        #MSGIDs to ignore from the Job Log
#omitjoblog="BRM10A1|BRM14A1|BRM15A7|CPC2402|CPFA09E|CPD37C3|CPD384E"       #Example MSGIDs to ignore from the Job Log
joblogsev='10'                                                              #Severity filter for the Job Log
omithstlog="'CPF0000'"                                                      #MSGIDs to ignore from the History Log
#omithstlog="'BRM14A1','BRM10A1'"                                           #Example MSGIDs to ignore from the History Log
hstlogsev='10'                                                              #Severity filter for the History Log
omitbrmlog="'CPF0000'"                                                      #MSGIDs to ignore from the BRMS Log
#omitbrmlog="'BRM14A1','BRM10A1'"                                           #Example MSGIDs to ignore from the BRMS Log
brmlogsev='10'                                                              #Severity filter for the BRMS Log

# Setup directory structure
mkdir -p $archivedir
mkdir -p $tempdir
mkdir -p $outputdir

# Cleanup of previous runs
rm $log
rm $out
rm $file1
rm $file2
rm $hstlog
rm $brmlog
rm $joblog
rm $hstlogtmp
rm $brmlogtmp
rm $joblogtmp
rm $msgidlist
rm $msgidtmp

# Creating new files
touch $log
touch $out
touch $file1
touch $file2
touch $hstlog
touch $brmlog
touch $joblog
touch $archivejoblog
touch $archivehstlog
touch $archivebrmlog
touch $hstlogtmp
touch $brmlogtmp
touch $joblogtmp
touch $msgidlist
touch $msgidtmp

# Setting preferred CCSIDs
setccsid 1208 $log
setccsid 1208 $out
setccsid 1208 $file1
setccsid 1208 $file2
setccsid 1208 $hstlog
setccsid 1208 $brmlog
setccsid 1208 $joblog
setccsid 1208 $archivejoblog
setccsid 1208 $archivehstlog
setccsid 1208 $archivebrmlog
setccsid 1208 $hstlogtmp
setccsid 1208 $brmlogtmp
setccsid 1208 $joblogtmp
setccsid 1208 $msgidlist
setccsid 1208 $msgidtmp

date >$log
echo "$LINENO"

########## Check for unsupported CCSID of current job ##########
ccsid=`system "DSPJOB" | grep 'Coded' | awk {'print $18'}`
if test $ccsid == 65535
then echo ccsid is set to unsupported value of $ccsid exiting script. >>$log
echo "CCSID is set to $ccsid change this value to 37 and try again."
exit
else echo ccsid value $ccsid is good. >>$log
fi

# Checking for required PARM
if [[ -z "$1" ]]
 then
  echo "Input is Empty provide a parm next time bye." >>$log
  exit
 else
  echo " PARM $1 $2 was provided" >>$log
fi
echo "$LINENO"

echo "Checking for BRMS SQL Services enabled" >>$log
system "DSPOBJD OBJ(QUSRBRM/LOG_INFO) OBJTYPE(*FILE)" >>/dev/null
if test $? == 1
 then system "INZBRM OPTION(*SQLSRVINZ)" >>$log 2>&1
  if test $? == 1
   then echo "Not able to INZ BRMS for SQL Services Check PTF prereqs again" >>$log
   exit
   else echo "INZ of BRMS for SQL Services completed" >>$log
  fi
 else echo "BRMS SQL Services already enabled" >>$log
fi
echo "$LINENO"

echo "Checking job information override" >>$log
if [[ "$1" == 'LAST' ]]
 then
  jobuc=`db2 "SELECT DISTINCT QUALIFIED_JOB_NAME, MESSAGE_TIMESTAMP FROM QUSRBRM.BRMS_LOG_INFO WHERE AREA ='BACKUP' AND CONTROL_GROUP IS NOT NULL AND MESSAGE_TIMESTAMP >= current timestamp - $numdays day ORDER BY MESSAGE_TIMESTAMP DESC LIMIT 1" | awk {'print $1'} | sed '4!d'`
   if test $? == 1
    then echo "Last job information not found in the last $numdays. Exiting script" >>$log
    exit
    else echo "Job $jobuc found" >>$log
   fi 
  echo "jobuc set as $jobuc" >>$log
 else
  echo "Input is $1" >>$log; jobuc=$1
fi
echo "$LINENO"

# Check for BRMS CTLG as $2
echo "Checking for BRMS Control Group parm" >>$log
if [[ "$1" == 'CTLG' ]]
 then
 echo "BRMS Control Group provided as $2 Running save" >>$log
  system "SBMJOB CMD(STRBKUBRM CTLGRP($2) SBMJOB(*NO)) JOB($2)" >$out
  sleep 10
  jobuc=`cat $out |grep CPC1221 | awk {'print $3'}`
  echo "jobuc set as $jobuc" >>$log
 else
  echo "BRMS Control Group not provided skipping Save" >>$log
fi
echo "$LINENO"

echo "Setting Lower case job information" >>$log 
joblc=`echo "$jobuc" | tr 'A-Z' 'a-z'`
echo "joblc set as $joblc" >>$log
echo "$LINENO"

echo "Checking for active job $joblc" >>$log
/usr/bin/ps -e | grep $joblc >>$log
echo "$LINENO"

while /usr/bin/ps -e | grep $joblc
  do
  date  >>$log
  echo "Job $joblc is still running, Checking again later" >>$log
  sleep 10
done
echo "$LINENO"

echo "Job $joblc has completed" >>$log
/usr/bin/ps -e | grep $joblc >>$log
echo "$LINENO"

echo "Display of history log for Job $jobuc sev $hstlogsev or greater" >>$log
# Optionally add MESSAGE_SECOND_LEVEL_TEXT to below SQL statement
db2 "SELECT MESSAGE_ID, SEVERITY, MESSAGE_TIMESTAMP, FROM_JOB, MESSAGE_TEXT FROM table(qsys2.history_log_info(CURRENT TIMESTAMP - $numdays DAY)) WHERE FROM_JOB ='$jobuc' AND MESSAGE_ID NOT IN("$omithstlog") AND SEVERITY >=$hstlogsev" >>$hstlog
if [[ "$?" == '1' ]]
 then hstlogresult='1'
 else cat $hstlog | sed 1,2d | sed '/-----/d' | sed 's/       //g' | grep -v '(S)' | sed '/^$/d' > $hstlogtmp && cp $hstlogtmp $hstlog
fi
echo "$LINENO"

echo "Display of brms log for job $jobuc sev $brmlogsev or greater" >>$log
# Optionally add MESSAGE_SECOND_LEVEL_TEXT to below SQL statement
db2 "SELECT MESSAGE_ID, MESSAGE_SEVERITY, QUALIFIED_JOB_NAME, CONTROL_GROUP, MESSAGE_TEXT FROM QUSRBRM.BRMS_LOG_INFO WHERE QUALIFIED_JOB_NAME='$jobuc' AND MESSAGE_ID NOT IN("$omitbrmlog") AND SEVERITY >=$brmlogsev" >>$brmlog
if [[ "$?" == '1' ]]
 then brmlogresult='1'
 else cat $brmlog | sed 1,2d | sed '/-----/d' | sed 's/       //g' | grep -v '(S)' | sed '/^$/d' > $brmlogtmp && cp $brmlogtmp $brmlog
fi
echo "$LINENO"

echo "Display of job log for job $jobuc sev $joblogsev or greater" >>$log
job="'"$jobuc"'"
echo "job set as $job" >>$log
splnum=`db2 "SELECT SPOOLED_FILE_NAME, FILE_NUMBER FROM QSYS2.OUTPUT_QUEUE_ENTRIES WHERE JOB_NAME=$job" | grep QPJOBLOG | awk {'print $2'}`
echo "splnum set as $splnum" >>$log
echo "catsplf -j $jobuc QPJOBLOG $splnum" >>$log
catsplf -j $jobuc QPJOBLOG $splnum | sed '/5770SS1/d; /Job name/d; /Job description/d; /MSGID/d; /To module/d; /To procedure/d; /Statement ./d; /From module/d; /From procedure/d' >$file1
echo "$LINENO"

cat $file1 | sed '
/^[ ][A-Z]/{
x
/./ {
x
s/^/\
/
x
}
x
}
h' >$file2
echo "$LINENO"

# Returns paragraph if SEV is greater than X and Omits MSGIDs defined above
pgraph() {
sed -e '/./{H;$!d;}' -e "x;/$1/!d" $file2 >>$joblog
}
echo "$LINENO"

cat $file2 | egrep "^[ ][A-Z]" | egrep -v $omitjoblog | awk -vm=${joblogsev} '$3 >= m' | awk '{ print $1 }' | sort | uniq | while read a
do
pgraph $a
done
echo "$LINENO"

# Check for empty logs to exclude from email
fileatt=''
echo "$LINENO"

echo $fileatt
if [[ "$hstlogresult" == '1' ]]
 then echo "No History log information found matching criteria" >>$log
 else fileatt="$fileatt ('$hstlog' *OCTET *TXT)"
fi
if [[ "$brmlogresult" == '1' ]]
 then echo "No BRMS Log information found matching criteria" >>$log
 else fileatt="$fileatt ('$brmlog' *OCT *TXT)"
fi
if [[ -s "$joblog" ]]
 then fileatt="$fileatt ('$joblog' *OCT *TXT)"
 else echo "No Job log information found matching criteria" >>$log
fi
if [[ -s "$file1" ]]
 then fileatt="$fileatt ('$file1' *OCT *TXT)"
 else echo "No Job log information found" >>$log
fi
if [[ -z "$fileatt" ]]
 then echo "No information found. Assuming job completed without errors and is no longer on the system" >>$log
 exit
 else echo "Information found sending email" >>$log
 fileatt="$fileatt ('$msgidlist' *OCT *TXT)"
fi
echo "$LINENO"

# List number of times each MSGID appears in Job Log
cat $file2 | cut -c'2-8','37-38'| sort | uniq | egrep -v NONE |sed 's/./& /7'| awk '{print $1" "$2}'| sed '/^[ ]/d'| while read a b
do
echo Number of times $a with Severity $b occurs " " |tr -d '\n' >>$msgidtmp; grep $a $file2 | wc -l  >>$msgidtmp
done
cat $msgidtmp | sort -k7 | sed '1!G;h;$!d' >$msgidlist
echo "$LINENO"

# Scrub of files before emailing
echo "Messages $hstlogsev or greater only" >>$hstlog
echo "Filtering the following Message IDs $omithstlog" >>$hstlog
echo "Messages $brmlogsev or greater only" >>$brmlog
echo "Filtering the following Message IDs $omitbrmlog" >>$brmlog
echo "Messages $joblogsev or greater only" >>$joblog
echo "Filtering the following Message IDs $omitjoblog" >>$joblog
echo "$LINENO"

system "SNDSMTPEMM RCP($emaillist) SUBJECT('BRMS logs') NOTE('BRMS logs') ATTACH($fileatt)"

# Copy current information into archive logs
cat $joblog >> $archivejoblog
cat $hstlog >> $archivehstlog
cat $brmlog >> $archivebrmlog
echo "$LINENO"

# Change log YYYY-MM-DD
# 2021-12-20 Start of Change log and Version 2021.12.20
# 2021-12-21 Added checks for empty files and no result sets
#            If found exclude them from the Email.
# 2021-12-22 Added several tmp files. Removed 2nd level text from SQL queries for BRM and HST log.
#            Created archive files for future global logging and reporting
# 2021-12-27 Added MSGIDLIST count process
# 2021-12-30 Added process to find Spool file number based on jobuc
#            Added additional logging
# 2021-12-31 Added MSGIDLIST to email, appended filters to each attachment, cleaned up hstlog and brmlog
#            Changed head to tac
# 2022-01-11 Added PATH setting. Changed SQL commands to use numdays var.
# 2022-01-19 Small change to the for loop syntax on the Checking for BRMS SQL Services section
#            Change to the submit job command, Change PARM to be required, added BRMS CTLG as PARM
#            Added extra echo statements to the log, hard coded path to ps command in /usr/bin
# 2022-01-22 Removed tac and head options.  They were being used in /QOpenSys/pkgs/bin provided by newer oss environment.
#            Changed the sort -k command -r is only provided by said oss.  added sed command to print in reverse order
#            Changed file name for log and out to match that of script name. Changes some working in some echo commands
# 2022-01-24 Added exit if jobuc not found, Added echo of LINENO
# 2023-06-21 Moved output files to subdir
#            Change file vars to include full path. added single quotes on the fileatt vars.
# 2024-07-31 Added check for CONTROL_GROUP IS NOT NULL