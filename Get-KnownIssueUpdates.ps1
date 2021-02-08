#############################################################################
# Author  : Tyler Cox
# 
# Special Thanks: Adapted from Jeff Hancock's script.
#
# Version : 1.1
# Created : 11/27/2020
# Modified : 02/08/2021
#
# Purpose : This script updates a wepbage that displays the current month's known
#           issue updates.
#
# Requirements: SCCM Console must be installed on the machine running this
#             
# Change Log:   Ver 1.1 - Reworked to group updates by KB. This helps limit the size
#                         of the html page created and makes it easier to read. Added
#                         more try/catch as well as logging.
#
#               Ver 1.0 - Initial release
#
#############################################################################

#Declare some variables
$logdir = $ENV:SystemRoot + "\Logs\KnownIssueUpdates\" #This is dynamic to the user
$log = $logdir + "Get-KnownIssueUpdates.log" #log file which saves date
$error.Clear()

#function for log writing
function Write-Log {
	param (
		[Parameter( Mandatory=$true)][string]$logdata,
		[Parameter( Mandatory=$false)][string]$logfile=$log
		)
	
	#Check to see if the specified log file exists
	$fileexist = Test-Path $logdir
	If ($fileexist -eq $false) {
		New-Item -ItemType Directory $logdir
        }
    #Does the log file exist?
    If ((Test-Path $log) -eq $False) {
            $item = New-Item -ItemType file "$log" | out-null
            }
    	#Prepare and write the data to the log file
	$now = Get-Date -format s
	$fileexist = Test-Path $log
	If ($fileexist -eq $True) {
		$logstring = $now+" >> "+$logdata
		$logstring | Out-File -Append $log
		}
	}#endfunc 

#Import Configuration Manager module
Try 
    {
        Write-Log -logdata "Importing the Config Manager module.."
        Import-Module ((Split-Path $env:SMS_ADMIN_UI_PATH)+'\configurationmanager.psd1') -ErrorAction Stop
    }
Catch 
    {
        Write-Log -logdata "Error! Failed to import Config Manager module! Please make sure the script is running on a computer with the Console installed!"
    }   

#Shift through some date functions to get our first and last days of the month
$CurrentDate = GET-DATE -Format "MM/dd/yyyy"  #current date
$FirstDayofMonth = GET-DATE $CURRENTDATE -Day 1 #First day of month 
$LastDayofMonth = GET-DATE $FirstDayofMonth.AddMonths(1).AddSeconds(-1) #Last day of month
$FDayofMonth = get-date $FirstDayofMonth -Format "MM/dd/yyyy" #format to easier reading
$LDayofMonth = get-date $LastDayofMonth -Format "MM/dd/yyyy" #format to easier reading
$CurrentMonth = Get-Date -UFormat %b #Current month abbreviated
$CurrentYear = (Get-Date).year
Write-Log -logdata "Current Month: $($CurrentMonth) $($CurrentYear)"
Write-Log -logdata "First day of the month: $($FDayofMonth)"
Write-Log -logdata "Last day of the month: $($LDayofMonth)"
$pageURL = "[http://yoururlgoeshere]" #This will be the local webpage URL. 
$IISLocation = "C:\inetpub\[yourIISfolderlocationgoeshere]\index.html"\index.html" #This is the location to the IIS folder and new index.html file

#Declare some variables
[string]$emailBody = "Please use the link below to review the Known Issues for this month's Microsoft Updates. Report any possible issues to the group.<br /><br />$($pageURL)<br /><br />This email is sent automatically. "
[string]$emailSubject = "$($CurrentMonth)-$($CurrentYear) - Known Issue Updates"
[string]$emailFrom = "[YourFromEmailGoesHere]"
[string]$emailTo = "[YourToEmailGoesHere]"
[string]$emailSMTPserver = '[YourSMTPserverGoesHere]'

#Get Site Code. Note: Console must be on this machine for this to work.
$SiteCode = Get-PSDrive -PSProvider CMSite
Write-Log -logdata "Site Code set as: $($SiteCode)"

#Set our drive to point to our SCCM environment
Set-Location "$($SiteCode.Name):"

#This pulls all updates we want for this month. This command uses the SCCM Console commandlet.
try 
    {
        Write-Log -logdata "Pulling software updates from Config Manager.."
        $SoftwareUpdates = Get-CMSoftwareUpdate -DatePostedMin $FDayofMonth -DatePostedMax $LDayofMonth -IsExpired $false  -Fast | Select @{E={$_.LocalizedDisplayName};L="Title"}, ArticleID, @{E={$_.LocalizedInformativeURL};L="URL"} |
        Where-Object { ($_.'Title' -notlike '*itanium*') -or ($_.'Title' -notlike '*beta*') -or ($_.'Title' -notlike '*lip*') -or ($_.'Title' -notlike '*language pack*') -or ($_.'Title' -notlike '*language interface pack*') -or ($_.'Title' -notlike '*media center*') -or ($_.'Title' -notlike '*pinyin*') -or ($_.'Title' -notlike '*user interface pack*')} 
        Write-Log -logdata "Found $($SoftwareUpdates.count) total Software Updates"
    }
catch
    {
        Write-Log -logdata "Error! Could not pull the software updates from Config Manager!"
    }

#Group the updates together by KB number. This helps us during sorting and prevents the HTML file from repeating the same KB numbers for different OSes
$GroupedSUs = $SoftwareUpdates | Group-Object -Property ArticleID
Write-Log -logdata "Grouped together the software updates into $($GroupedSUs.Count) groups"

#This is our array that will hold all the HTML tables
$html = @()

#Loop through each group
foreach ($group in $GroupedSUs)
    {   
        $tablenew = $null
        $Testcount += 1
        Write-Log -logdata "Proceessing Group Name: $($Group.Name)"
        $count = 1 #Count variable used in the loops

        #Loop through each software update
        foreach ($SoftwareUpdate in $group.Group)
            {
                Write-Log -logdata "Processing Software Update: $($SoftwareUpdate.Title)"
                $matches = $null #used in regex later. Nulling it out each time to prevent bad regex data.
                $KnownIssue1 = $null
                $KnownIssue2 = $null
                [string]$SUTitle = $SoftwareUpdate.Title #Get the Title of the update
                [string]$SUArticleID = $SoftwareUpdate.ArticleID #Get the ArticleID of the update. ex. KB4507280
                [string]$SUURL = $SoftwareUpdate.URL #This gets the URL for the update
   
                #We don't need to be in the ConfigMgr drive anymore so let's get out of it
                Set-Location "C:"

                #This creates a web request using Microsoft's API for the update
                Try
                    {
                        $KBArticle = Invoke-WebRequest -Uri "https://support.microsoft.com/app/content/api/content/help/en-us/$($SUArticleID)" -ContentType 'application/json' | ConvertFrom-JSON
                    }
                Catch
                    {
                        Write-Log -LogData "Failed to initiate web request. Most likely this is because this is a 3rd party update"
                        #No need to continue!
                        $count += 1 #Add to count because we are skipping out of the loop early (it normaly gets added further down)
                        break
                    }

                #Microsoft LOVES to change their own wording between updates. Let's try to catch them all with this
                [string]$KnownIssue1 = ($KBArticle.details.body | Where-Object {$_.Title -eq "Known issues in this update"}).Content
                [string]$KnownIssue2 = ($KBArticle.details.body | Where-Object {$_.Title -eq "Known issues in this security update"}).Content            

                #Here we are proceeding ONLY if we found useful info under the KnownIssues in the web request. 
                If((($KnownIssue1) -OR ($KnownIssue2)) -AND (($knownissue1 -notlike "*not*aware of any issue*") -AND ($knownissue2 -notlike "*not*aware of any issue*")))
                    {
                        If ($Count -eq 1)
                            {                                  
                                #Decide which KnownIssue wording we used, and set our variable accordingly
                                If ($KnownIssue1)
                                    {
                                        $Table = $KnownIssue1
                                    }
                                ElseIf ($KnownIssue2)
                                    {
                                        $Table = $KnownIssue2
                                    }   
            
                                #Some more wording changes caused this. Have to search if the class name for the table is different
                                If ((Select-String -InputObject $table -pattern '<table class="table ng-scope">').matches.value)
                                    {
                                        $tablereplace = '<table class="table ng-scope">'
                                    }
                                Else
                                    {
                                        $tablereplace = '<table class="table">'
                                    }
                                
                                        #Set a new variable to our table data
                                        Write-Log -logdata "Warning! This is a known issue update!"
                                        $Script:tablenew = $table
                                        [regex]$patternTR = '<tr>' #Regex used for the KBTitle (more info later)
                                        [regex]$patternTD = '<td><strong>' #Regex used for the "symptom" and "workaround" headers (more later)
                                        [regex]$patternCrapTable = '<tr role="row">[\s\S]*?<\/tr>' #Regex used to fix MS wording issues for the Update Title (more later)
                                        [regex]$patternBadLinks = '<td>This issue is resolved in <[\s\S]*?<\/td>' #Regex used to fix bad/dead links (more later)
                                        [regex]$patternBadLinksKB = '(?<=blank">KB)[\s\S]*?(?=<\/a>)' #Regex to get the KB for the dead link (more later)
                                        [regex]$patternAffSoftSingle = "</tbody>" #Regex to get teh end of the table for putting Affected Software list (more later)
                                        [regex]$patternAffSoftMultiple = "</a></td></tr></tbody>" #Regex to get the end of the table for putting Affected Software list (more later)
                                        $tablenew = $tablenew.replace($tablereplace,'<table class="table" border="2" cellspacing="3" cellpadding="5">') #Replace parts of the string to create a class for the table as well as border, cellspacing, etc.
                                        #This if block is to fix the title. MS moves the title below the Symptom/Workaround. 
                                        IF ($tablenew -match $patternCrapTable)
                                            {
                                                $tablenew = $patternCrapTable.replace($tablenew,'',1) #Wipe out the data
                                                #replace the data with new, fixed data to match the other tables. Also creating the title cell to span across both columns.
                                                $tablenew = $PatternTR.replace($tablenew,"<tr><td class = KBTitle colspan = '2' >KB$SUArticleID</td></tr><tr><td class=headers><strong>Symptom</strong></td><td class=headers><strong>Workaround</strong></td></tr>",1)
                                            }
                                        else
                                            {
                                                $tablenew = $PatternTR.replace($tablenew,"<tr><td class = KBTitle colspan = '2' >KB$SUArticleID</td></tr><tr>",1) #If data isn't broke, just create the title. Also creating the title cell to span across both columns. 
                                            }
                                        
                                        $tablenew = $PatternTD.replace($tablenew,"<td class=headers><strong>",2) #this creates/places the "headers" class (used in CSS file) on the Symptom/Workaround cells.
                                        #This if block is to find the broken links.
                                        If ($tablenew -match $patternBadLinks) 
                                            {
                                                $BadLinkKB = $tablenew -match $patternBadLinksKB #If the KB article is found, set it as a variable
                                                $BadLinkKB = $matches[0] #Set that variable again to the actual value
                                            }
                                        $tablenew = $PatternBadLinks.replace($tablenew,"<td>This issue is resolved in <a href=https://support.microsoft.com/en-us/help/$BadLinkKB>KB$BadLinkKB</a>.</td>") #Replace the broken link with the working one  
                                        
                                        $tablenew = $patternAffSoftSingle.replace($tablenew,"<tr><td class=AffSoft>Affected Products/Operating Systems:</td><td class=AffSoft><a href=$SUURL>$SUTitle</a></td></tr></tbody>")

                                        If ($Count -eq $Group.Count)
                                            {
                                                Write-Log -logdata "Processed last update of this group!"
                                                #Write-Host "Adding to HTML" -ForegroundColor Green
                                                $html += $tablenew #add each new table to the HTML variable 
                                            }
                                           
                                        $Count += 1 #Add 1 to the count. This is done to show we are moving on to the second update in the "group"
                            }
                        ElseIf ($Count -eq $Group.Count) #We've processed all upates in the group, now to write them to the html file
                            {
                                Write-Log -logdata "Processed last update of this group!"
                                $tablenew = $patternAffSoftMultiple.replace($tablenew,"<br><a href=$SUURL>$SUTitle</a></td></tr></tbody>",1)
                                #Write-Host "Adding to HTML" -ForegroundColor Green
                                $html += $tablenew #add each new table to the HTML variable
                            }
                        else #We aren't at the beginning or the end, so do the middle!
                            {
                                $tablenew = $patternAffSoftMultiple.replace($tablenew,"<br><a href=$SUURL>$SUTitle</a></td></tr></tbody>",1)
                                $Count += 1
                            }
                    }    
                ElseIF ($Count -eq $Group.Count)
                    {
                        Write-Log -Logdata "Processed last update of this group!"
                    }
                Else
                    {
                        $Count += 1
                    }
                           
            }#EndForEach 
    }

Write-log -logdata "==========================================================================="



#Get the template file
$template = (Get-Content -Path C:\inetpub\SUKnownIssues\template.html -raw)
#Place variables and new $html into the template file and rename it as index.html
Invoke-Expression "@`"`r`n$template`r`n`"@" | Set-Content -Path $IISLocation

#Let's send an email to the group to remind them to look at these upates!
Send-MailMessage -To $emailTo -From $emailFrom -BodyAsHtml $emailBody -Subject $emailSubject -SmtpServer $emailSMTPserver -Priority High
