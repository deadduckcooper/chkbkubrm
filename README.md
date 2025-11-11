# About chkbkubrm
A Unique way to report on the results of a BRMS save job on an IBM i system by filter out the messages you expect to see. This resutls in only showing you messages you did not expect to see.

## Origins
I created this script around the year 2021 to save time seaching thru job logs for problems, and noticing operations staff missing problems. This script is intended to run after each BRMS save job either as an *EXIT at the end of the control group. However I have seen people run it from the scheduler and manually. This script could also be used to search any job log, not just a BRMS save job log.

## Warning
This is my first time using git. The instructions below were created assumed someone manually transfered the script to the IFS.

## Instructions
When calling this program you have the option to pass the parms of
- LAST This will query the BRMS database for the last save job that has run. Example chkbkubrm.sh LAST
- Specific job information. Example chkbkubrm.sh 123456/USER/WEEKLY
- CTLG + Name of BRMS control group and that save will run now. Example chkbkubrm.sh CTLG WEEKLY

## Tips for Setting the Special Variables
The key to quickly finding problems in the job log is to properally identify message id's that you don't care about. To do this can take a little bit of time, but once set will save you time, and help you resolve problems with your saves. 

After you have the script in the IFS update your email address in the Specail Vars section and run the script as is with no filtering. Review the msgidlist.txt file, this file contains a uniq list of every message id from your saves job log, sorted by servity. Review each message id in the full job log file and decide if that is a message you care to see every time the save completes with errors or fails.  Once done, use your list of message id's you don't care about and set the omitjoblog, omithstlog, and omitbrmlog variables.

You can also set a servity filter for each as you like. Keep in mind some messages you care about might have a low servity, one such example is listed at the end of this document.

## Setup
From qsh, create the directory structor for this script. I use the directory "/scripts/chkbkubrm"
```
mkdir /scripts
```
```
mkdir /scripts/chkbkubrm
```
```
cd /scripts/chkbkubrm
```
```
touch chkbkubrm.sh
```
```
setccsid 1208 chkbkubrm.sh
```
Download the chkbkubrm script and replace the file in the IFS you just created, or copy and paste the text into our IFS file. Again, as of now i'm not sure how to get the file to the IFS via git. Once I figure that out I will updated this file.
                                                 
## Manually test commands from IBM ACS Run SQL Scripts to make sure they work before running the script.
```
CL: DSPOBJD OBJ(QUSRBRM/LOG_INFO) OBJTYPE(*FILE);
```
```
SELECT DISTINCT QUALIFIED_JOB_NAME, MESSAGE_TIMESTAMP FROM QUSRBRM.BRMS_LOG_INFO WHERE AREA ='BACKUP' AND MESSAGE_TIMESTAMP >= current timestamp - 1 day
ORDER BY MESSAGE_TIMESTAMP DESC LIMIT 1;
```

Replace $JOBINFO with the qualified job name returned from the previous command for the following SQL statments.

Check history log
```
SELECT MESSAGE_ID, SEVERITY, MESSAGE_TIMESTAMP, FROM_JOB, MESSAGE_TEXT FROM table(qsys2.history_log_info(CURRENT TIMESTAMP - 1 DAY)) WHERE FROM_JOB ='$JOBINFO' AND MESSAGE_ID NOT IN('CPF0000') AND SEVERITY >=0 LIMIT 1;
```
Check BRMS log
```
SELECT MESSAGE_ID, MESSAGE_SEVERITY, QUALIFIED_JOB_NAME, CONTROL_GROUP, MESSAGE_TEXT FROM QUSRBRM.BRMS_LOG_INFO WHERE QUALIFIED_JOB_NAME='$JOBINFO' AND MESSAGE_ID NOT IN('CPF0000') AND SEVERITY >=0 LIMIT 1;
```
Check read of spool file job log
```
SELECT SPOOLED_FILE_NAME, FILE_NUMBER FROM QSYS2.OUTPUT_QUEUE_ENTRIES WHERE JOB_NAME='$JOBINFO';
```
Use your email address and make sure you recieve the test email.
```
CL: SNDSMTPEMM RCP(email.address1@example.com) SUBJECT('Test') NOTE('Test');
```

## Example as to why we don't just filter for greater than SEV x.  You might miss things you care about.
```
Message ID . . . . . . . . : BRM1100       Severity . . . . . . . : 10
Message . . . . :   IPL cannot be started.
Cause . . . . . :   Current time 23:48 is not within IPL limits 00:01 and 07:00.              
```
