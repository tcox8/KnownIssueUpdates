# KnownIssueUpdates
This script will pull the monthly updates and find any known issues. The output is parsed and built into a webpage. An email is sent to remind the receiver to look at the webpage. The script should be setup to run as a scheduled task every second tuesday of the month. 


The output will look like this. <br/>




# Requirements
Powershell 3.0<br/>
ConfigManager Console on the machine that runs this script<br/>
IIS setup with the file from the "IIS" folder<br/>

# What to Edit to Make This Work For You
Varibales - edit $pageURL to point to your desired webpage (create a cname in dns for this), <br/>
            edit $IISLocation to your IIS folder, <br/>
            edit $emailSMTPserver to your SMTP server, <br/>
            edit $emailTo to who you want to receive the email, <br/>
            edit $emailFrom to who you want the from/reply email address to be <br/>
