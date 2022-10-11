#!/usr/local/bin/perl
our $VERSION = '1.0.6';

use strict;
use REST::Client;
use Getopt::Std;
use JSON;
use Term::ReadKey;
use Time::HiRes qw(gettimeofday);
use POSIX;
use Switch;

#Set Environment Variable to no verify certs
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;

#Variables
my %options=();
my $errCode=0;
#$options{p}="admin"; # Hard set password
my $client=REST::Client->new();
my $accessToken;
my $tokenType;
my $authCookie;
my $sizeType="GB";
my $sizeValue=1073741824;
my %fields= (
  'OT'    => 'Object Type',
  'ON'    => 'Object Name',
  'SN'    => 'Source Name',
  'NSS'   => 'Number of Snapshots',
  'LRS'   => 'Last Run Status',
  'ST'    => 'Schedule Type',
  'LRST'  => 'Last Run Start Time',
  'LRET'  => 'Last Run End Time',
  'FSSS'  => 'First Successful Snapshot',
  'FFSS'  => 'First Failed Snapshot',
  'LSSS'  => 'Latest Successful Snapshot',
  'LFSS'  => 'Latest Failed Snapshot',
  'NOS'   => 'Number of Success',
  'NOE'   => 'Number of Errors',
  'NOW'   => 'Number of Warnings',
  'SR'    => 'Success Rate',
  'DR'    => 'Data Read',
  'LP'    => 'Logical Protected',
);

#Subs
sub help(){
  print <<EOF;
usage: $0 -c clusterVIP/Hostname -u user [-dhow] [-s TB|GB|MB|KB|B] [-f All | OT:ON:SN:NSS:LRS:ST:LRST:LRET:FSSS:FFSS:LSSS:LFSS:NOS:NOE:NOW:SR:DR:LP] [-t Hours] [-p password]
    -h - Help Menu
    -d - Debug Mode
    -o - Object Report
    -s - Size Representation (TB,GB,MB,KB,B) (Default: GB)
    -f - Fields (Default: All)
    -w - HTML format (Default: CSV)
    -t - Time Hours ago (Default: 24)
    -c cluster - Cohesity cluster VIP/IP/Hostname
    -u user - Cohesity user
    -p password - Cohesity user password

Fields:
    OT   - Object Type
    ON   - Object Name
    SN   - Source Name
    NSS  - Number of Snapshots
    LRS  - Last Run Status
    ST   - Schedule Type
    LRST - Last Run Start Time
    LRET - Last Run End Time
    FSSS - First Successful Snapshot
    FFSS - First Failed Snapshot
    LSSS - Latest Successful Snapshot
    LFSS - Latest Failed Snapshot
    NOS  - Number of Success
    NOE  - Number of Errors
    NOW  - Number of Warnings
    SR   - Success Rate
    DR   - Data Read
    LP   - Logical Protected
EOF
  exit(1);
}

sub getObjectInfo{
  my ($seconds, $microseconds) = gettimeofday;
  my $currTime = int($seconds * 1000000 + $microseconds);
  my $pastTime = int ($currTime - $options{t}*3600000000);
  print "CurrentTime: $currTime\n" if exists $options{d};
  print "PastTime: $pastTime\n" if exists $options{d};
  $client=REST::Client->new(); 
  $client->setHost("https://$options{c}"); #Set host
  $client->addHeader("Accept", "application/json");
  $client->addHeader("Authorization", "$tokenType $accessToken"); #Authorize request
  $client->GET('/irisservices/api/v1/public/reports/protectionSourcesJobsSummary?startTimeUsecs='.$pastTime.'&endTimeUsecs='.$currTime);
  print 'Response: '.$client->responseContent()."\n" if exists $options{d};
  print 'Response status: '.$client->responseCode()."\n" if exists $options{d};
  my $response=decode_json $client->responseContent();
  my @report = {};
  #print "$response->{'protectionSourcesJobsSummary'}->[0]->{'registeredSource'}\n";
  for(my $i=0;$i<=$#{$response->{'protectionSourcesJobsSummary'}};$i++){
    my %vLookup=(
    'vmWareProtectionSource' => 'VMware',
    'physicalProtectionSource' => 'Physical',
    'hypervProtectionSource' => 'HyperV',
    'sqlProtectionSource' => 'SQL',
    'pureProtectionSource' => 'Pure',
    'azureProtectionSource' => 'Azure',
    'netappProtectionSource' => 'Netapp',
    'nasProtectionSource' => 'NAS',
    'acropolisProtectionSource' => 'Acropolis',
    'isilonProtectionSource' => 'Isilon',
    'kvmProtectionSource' => 'KVM',
    'awsProtectionSource' => 'AWS',
    'oracleProtectionSource' => 'Oracle',
    'flashBladeProtectionSource' => 'FlashBlade',
    'hyperFlexProtectionSource' => 'HyperFlex',
    'office365ProtectionSource' => 'Office365',
    'viewProtectionSource' => 'View',
    );
    for(sort keys %vLookup){
      if (exists($response->{'protectionSourcesJobsSummary'}->[$i]->{'protectionSource'}{"$_"}{'name'})){
        $report[$i]->{'ON'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'protectionSource'}{'name'};
        $report[$i]->{'OT'}=$vLookup{$_};
      } elsif(exists($response->{'protectionSourcesJobsSummary'}->[$i]->{'protectionSource'}{"$_"}{'type'})){
        $report[$i]->{'ON'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'protectionSource'}{'name'};
        $report[$i]->{'OT'}=$vLookup{$_};
      }
    }
    $report[$i]->{'SN'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'registeredSource'};
    $report[$i]->{'NSS'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'numSnapshots'};
    $report[$i]->{'LRS'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'lastRunStatus'};
    $report[$i]->{'LRS'}=~s/^.//;
    $report[$i]->{'ST'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'lastRunType'};
    $report[$i]->{'LRST'}=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($response->{'protectionSourcesJobsSummary'}->[$i]->{'lastRunStartTimeUsecs'}/1000/1000));
    $report[$i]->{'LRET'}=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($response->{'protectionSourcesJobsSummary'}->[$i]->{'lastRunEndTimeUsecs'}/1000/1000));
    $report[$i]->{'FSSS'}=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($response->{'protectionSourcesJobsSummary'}->[$i]->{'firstSuccessfulRunTimeUsecs'}/1000/1000));
    $report[$i]->{'FFSS'}=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($response->{'protectionSourcesJobsSummary'}->[$i]->{'firstFailedRunTimeUsecs'}/1000/1000));
    $report[$i]->{'LSSS'}=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($response->{'protectionSourcesJobsSummary'}->[$i]->{'lastSuccessfulRunTimeUsecs'}/1000/1000));
    $report[$i]->{'LFSS'}=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($response->{'protectionSourcesJobsSummary'}->[$i]->{'lastFailedRunTimeUsecs'}/1000/1000));
    $report[$i]->{'NOS'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'numSnapshots'}-$response->{'protectionSourcesJobsSummary'}->[$i]->{'numErrors'}-$response->{'protectionSourcesJobsSummary'}->[$i]->{'numWarnings'};
    $report[$i]->{'NOE'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'numErrors'};
    $report[$i]->{'NOW'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'numWarnings'};
    $report[$i]->{'SR'}=$report[$i]->{'NOS'}/$response->{'protectionSourcesJobsSummary'}->[$i]->{'numSnapshots'}*100;
    $report[$i]->{'DR'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'numDataReadBytes'};
    $report[$i]->{'LP'}=$response->{'protectionSourcesJobsSummary'}->[$i]->{'numLogicalBytesProtected'};
  }
  if($options{f} eq 'All' || $options{f} eq 'all'){
    print "<HTML><STYLE> table {border-collapse: collapse; border: 1px solid black;} tr:hover { background: lightgreen; } th {padding-left: 5px; padding-right: 5px;padding-bottom: 0px;padding-top: 0px;}</STYLE><TABLE BORDER=1 class=\"w3-table w3-striped\"><TR>" if exists $options{w};
    print "<TH>".$fields{OT}."</TH>" if exists $options{w};
    print "<TH>".$fields{ON}."</TH>" if exists $options{w};
    print "<TH>".$fields{SN}."</TH>" if exists $options{w};
    print "<TH>".$fields{NSS}."</TH>" if exists $options{w};
    print "<TH>".$fields{LRS}."</TH>" if exists $options{w};
    print "<TH>".$fields{ST}."</TH>" if exists $options{w};
    print "<TH>".$fields{LRST}."</TH>" if exists $options{w};
    print "<TH>".$fields{LRET}."</TH>" if exists $options{w};
    print "<TH>".$fields{FSSS}."</TH>" if exists $options{w};
    print "<TH>".$fields{FFSS}."</TH>" if exists $options{w};
    print "<TH>".$fields{LSSS}."</TH>" if exists $options{w};
    print "<TH>".$fields{LFSS}."</TH>" if exists $options{w};
    print "<TH>".$fields{NOS}."</TH>" if exists $options{w};
    print "<TH>".$fields{NOE}."</TH>" if exists $options{w};
    print "<TH>".$fields{NOW}."</TH>" if exists $options{w};
    print "<TH>".$fields{SR}."</TH>" if exists $options{w};
    print "<TH>".$fields{DR}."</TH>" if exists $options{w};
    print "<TH>".$fields{LP}."</TH>" if exists $options{w};
    print "</TR><TR>" if exists $options{w};
    
    for(my $j=0;$j<=$#report;$j++){
      my $rowColor;
      if($report[$j]->{'LRS'} eq 'Success'){
        $rowColor='"green"';
      } else {
        $rowColor='"red"';
      }
      print $report[$j]->{'OT'}."," if !exists $options{w};
      print "<TR bgcolor=".$rowColor."><TD>".$report[$j]->{'OT'}."</TD>" if exists $options{w};
      print $report[$j]->{'ON'}."," if !exists $options{w};
      print "<TD>".$report[$j]->{'ON'}."</TD>" if exists $options{w};
      print $report[$j]->{'SN'}."," if !exists $options{w};
      print "<TD>".$report[$j]->{'SN'}."</TD>" if exists $options{w};
      print $report[$j]->{'NSS'}."," if !exists $options{w};
      print "<TD>".$report[$j]->{'NSS'}."</TD>" if exists $options{w};
      print $report[$j]->{'LRS'}."," if !exists $options{w};
      print "<TD>".$report[$j]->{'LRS'}."</TD>" if exists $options{w};
      print $report[$j]->{'ST'}."," if !exists $options{w};
      print "<TD>".$report[$j]->{'ST'}."</TD>" if exists $options{w};
      print $report[$j]->{'LRST'}."," if !exists $options{w};
      print "<TD align=right>".$report[$j]->{'LRST'}."</TD>" if exists $options{w};
      print $report[$j]->{'LRET'}."," if !exists $options{w};
      print "<TD align=right>".$report[$j]->{'LRET'}."</TD>" if exists $options{w};
      print $report[$j]->{'FSSS'}."," if !exists $options{w};
      print "<TD align=right>".$report[$j]->{'FSSS'}."</TD>" if exists $options{w};
      print $report[$j]->{'FFSS'}."," if !exists $options{w};
      print "<TD align=right>".$report[$j]->{'FFSS'}."</TD>" if exists $options{w};
      print $report[$j]->{'LSSS'}."," if !exists $options{w};
      print "<TD align=right>".$report[$j]->{'LSSS'}."</TD>" if exists $options{w};
      print $report[$j]->{'LFSS'}."," if !exists $options{w};
      print "<TD align=right>".$report[$j]->{'LFSS'}."</TD>" if exists $options{w};
      print $report[$j]->{'NOS'}."," if !exists $options{w};
      print "<TD align=right>".$report[$j]->{'NOS'}."</TD>" if exists $options{w};
      print $report[$j]->{'NOE'}."," if !exists $options{w};
      print "<TD align=right>".$report[$j]->{'NOE'}."</TD>" if exists $options{w};
      print $report[$j]->{'NOW'}."," if !exists $options{w};
      print "<TD align=right>".$report[$j]->{'NOW'}."</TD>" if exists $options{w};
      printf "%.1f,", $report[$j]->{'SR'} if !exists $options{w};
      printf "<TD align=right>%.1f</TD>", $report[$j]->{'SR'} if exists $options{w};
      printf "%.1f%s,",$report[$j]->{'DR'}/$sizeValue,$sizeType if !exists $options{w};
      printf "<TD align=right>%.1f%s</TD>",$report[$j]->{'DR'}/$sizeValue,$sizeType if exists $options{w};
      printf "%.1f%s\n",$report[$j]->{'LP'}/$sizeValue,$sizeType if !exists $options{w};
      printf "<TD align=right>%.1f%s</TD></TR>",$report[$j]->{'LP'}/$sizeValue,$sizeType if exists $options{w};
    }
  } else {
    my @cols=split(':',$options{f});
    print "<HTML><STYLE> table {border-collapse: collapse; border: 1px solid black;} tr:hover { background: lightgreen; } th {padding-left: 5px; padding-right: 5px;padding-bottom: 0px;padding-top: 0px;}</STYLE><TABLE BORDER=1 class=\"w3-table w3-striped\"><TR>" if exists $options{w};
    foreach(@cols){
      print "<TH>".$fields{$_}."</TH>" if exists $options{w};
    }
    print "</TR>" if exists $options{w};
    for (my $j=0;$j<=$#report;$j++){
      my $rowColor;
      if($report[$j]->{'LRS'} eq 'Success'){
        $rowColor='"green"';
      } else {
        $rowColor='"red"';
      }
      print "<TR bgcolor=".$rowColor.">" if exists $options{w};
      foreach(@cols){
        if($cols[$#cols] eq $_){
          if($_ eq "LP" || $_  eq "DR" || $_ eq "SR"){
            printf "%.1f\n", $report[$j]->{$_}/$sizeValue if !exists $options{w};
            printf "<TD align=right>%.1f</TD></TR>", $report[$j]->{$_}/$sizeValue if exists $options{w};
          } elsif($_ eq "NOS" || $_ eq "NOE" || $_ eq "NOW" || $_ eq "NSS" || $_ eq "SR") {
            print $report[$j]->{$_}."\n" if !exists $options{w};
            print "<TD align=right>".$report[$j]->{$_}."</TD></TR>" if exists $options{w};
          } else {
            print $report[$j]->{$_}."\n" if !exists $options{w};
            print "<TD>".$report[$j]->{$_}."</TD></TR>" if exists $options{w};
          }
        } else {
          if($_ eq "LP" || $_  eq "DR" || $_ eq "SR"){
            printf "%.1f,", $report[$j]->{$_}/$sizeValue if !exists $options{w};
            printf "<TD align=right>%.1f</TD>", $report[$j]->{$_}/$sizeValue if exists $options{w};
          } elsif($_ eq "NOS" || $_ eq "NOE" || $_ eq "NOW" || $_ eq "NSS" || $_ eq "SR") {
            print $report[$j]->{$_}."," if !exists $options{w}; 
            print "<TD align=right>".$report[$j]->{$_}."</TD>" if exists $options{w}; 
          } else {
            print $report[$j]->{$_}."," if !exists $options{w}; 
            print "<TD>".$report[$j]->{$_}."</TD>" if exists $options{w}; 
          }
        }
      }
    }
    print "</TABLE></HTML>" if exists $options{w};
    print "\n";
  }
} 

sub authorize{
  #Try SSL Disable old method
  #$client->getUseragent()->ssl_opts( SSL_verify_mode => 0, verify_hostname => 0 );
  #Set Host
  $client->setHost("https://$options{c}");
  $client->addHeader("Accept", "application/json", "Content-Type", "application/json");
  #Check for authorization token cookie
  print "$authCookie\n" if exists $options{d};
  my $authLine;
  if(-e $authCookie){
    #Check if the authentication cookie exists and is valid
    open(FH, "<", "$authCookie"); #Open file for read access
    foreach(my $line=<FH>){
      print "Line: $line\n" if exists $options{d};
      ($tokenType, $accessToken)=split(/,/, $line);
      print "Type: $tokenType\nToken: $accessToken\n" if exists $options{d};
    }
    close(FH);
    #Check for invalid or expired token
    my $testAccess=REST::Client->new();
    $testAccess->setHost("https://$options{c}");
    $testAccess->addHeader("Accept", "application/json");
    $testAccess->addHeader("Authorization", "$tokenType $accessToken");
    #$testAccess->GET('/irisservices/api/v1/public/alerts?alertSeverityList[]=kCritical&alertCategoryList[]=kBackupRestore&alertStateList[]=kOpen');
    $testAccess->GET('/irisservices/api/v1/public/basicClusterInfo');
    print "Code: ".$testAccess->responseCode()."\n" if exists $options{d};
    print "Content: ".$testAccess->responseContent()."\n" if exists $options{d};
    #Check for successful status 200-299
    if($testAccess->responseCode() >= 300){
      unlink $authCookie; #if access token is expired or invalid remove cookie and request new token
      requestToken();
    }
  } else {
    #Request token since cookie doesn't exist
    requestToken(); 
  }
  # Valid Cookie so set tokentype and accesstoken variables
  open(FH, "<", "$authCookie"); #Open file for read
  foreach(my $line = <FH>){
    print "Line: $line\n" if exists $options{d};
    ($tokenType, $accessToken)=split(/,/, $line);
    print "Type: $tokenType\nToken: $accessToken\n" if exists $options{d};
  }
  close(FH); #Close the open file
  print "AccessToken: $accessToken\n" if exists $options{d};
  print "TokenType: $tokenType\n" if exists $options{d};
} 

sub requestToken{   
  #Request new authorization Token
  $client->POST('/irisservices/api/v1/public/accessTokens','{"domain" : "LOCAL","username" : "'.$options{u}.'","password" : "'.$options{p}.'"}');
  die $client->responseContent() if( $client->responseCode() >= 300 );
  open(FH,">$authCookie");
  my $test=decode_json($client->responseContent());
  print FH "$test->{'tokenType'},$test->{'accessToken'}";
  close(FH);
  print 'Response: '.$client->responseContent()."\n" if exists $options{d};
  print 'Response status: '.$client->responseCode()."\n" if exists $options{d};
  foreach ( $client->responseHeaders() ) {
    print 'Header: '.$_.'='.$client->responseHeader($_)."\n" if exists $options{d};
  }
}

#Main
getopts("hdwc:u:p:s:of:t:", \%options);

# Check for client switch and IP/Host
if (exists $options{c} && $options{c} ne ""){
  print "Cluster: $options{c}\n" if exists $options{d};
  $authCookie=$ENV{"HOME"} . "/.cohesity.$options{c}.auth";
} else {
  print "Error: Cluster not specified, please provide cluster information\n";
  help;
  exit(2);
}

#Check for help switch
if(exists $options{h}){
  help;
  exit(1);
}

if(exists $options{s} && $options{s} ne ""){
  switch($options{s}) {
    case "TB" {$sizeType=$options{s}; $sizeValue=1099511627776;}
    case "GB" {$sizeType=$options{s}; $sizeValue=1073741824;}
    case "MB" {$sizeType=$options{s}; $sizeValue=1048576;}
    case "KB" {$sizeType=$options{s}; $sizeValue=1024;}
    case "B"  {$sizeType=$options{s}; $sizeValue=1;}
  }  
}


#Check for user and prompt for password if necessary
if(exists $options{u} && $options{u} ne ""){
  if(exists $options{p}){
    print "User: $options{u}\nPassword: $options{p}\n" if exists $options{d};
  }else{
    if(-e $authCookie){
      #print "Authentication cookie exists you can delete the cookie $authCookie to prompt for password\n";
      #exit(4);
    } else {
      print "Please enter password: ";
      ReadMode('noecho');
      chomp ($options{p} = <STDIN>);
      print "\n";
      ReadMode(0);
      print "\nUser: $options{u}\nPassword: $options{p}\n" if exists $options{d};
    }
  }
} else {
  print "Error: User not specified\n";
  help;
  exit(3);
}

authorize();
getObjectInfo();
