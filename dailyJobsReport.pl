#!/usr/bin/perl

our $VERSION = '1.0.6';

use strict;
use REST::Client;
use Getopt::Std;
use JSON;
use Term::ReadKey;
use Time::HiRes qw(gettimeofday);
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
my $msg;
my $sizeType="GB";
my $sizeValue=1073741824;
my $alertStateList;
my $alertState;
my $alertCategoryList;
my $alertCategory;
my $alertsSeverityList;
my $alertsSeverity;

#Subs
sub help(){
  print <<EOF;
usage: $0 -c clusterVIP/Hostname -u user [-dhj] [-s TB|GB|MB|KB|B] [-p password]
    -h - Help Menu
    -d - Debug Mode
    -j - Jobs Report
    -s - Size Representation (TB,GB,MB,KB,B)
    -c cluster - Cohesity cluster VIP/IP/Hostname
    -u user - Cohesity user
    -p password - Cohesity user password
EOF
  exit(1);
}

sub getSourceInfo(){
  my ($seconds, $microseconds) = gettimeofday;
  my $totalSourceSizeBytes;
  my $totalBytesReadFromSource;
  my $totalLogicalBackupSizeBytes;
  my $totalPhysicalBackupSizeBytes;
  print "Seconds: $seconds\nMicroseconds: $microseconds\n" if exists $options{d};
  $client=REST::Client->new(); 
  $client->setHost("https://$options{c}"); #Set host
  $client->addHeader("Accept", "application/json");
  $client->addHeader("Authorization", "$tokenType $accessToken"); #Authorize request
  $client->GET('/irisservices/api/v1/public/protectionSources/virtualMachines?protected=true');
  print 'Response: '.$client->responseContent()."\n" if exists $options{d};
  print 'Response status: '.$client->responseCode()."\n" if exists $options{d};
  my $vmProtectedSources=decode_json $client->responseContent();  
  my $vmProtectedCount=$#{$vmProtectedSources} + 1; # Count sources for output
  $client->GET('/irisservices/api/v1/public/protectionSources/virtualMachines?protected=false');
  my $vmTotalSources=decode_json $client->responseContent();  
  my $vmTotalCount=$#{$vmTotalSources} + 1; # Count sources for output
  my $totalCount=int($vmProtectedCount + $vmTotalCount);
  print "VM Count: $vmProtectedCount\n" if exists $options{d};
  $client=REST::Client->new(); 
  $client->setHost("https://$options{c}"); #Set host
  $client->addHeader("Accept", "application/json");
  $client->addHeader("Authorization", "$tokenType $accessToken"); #Authorize request
  $client->GET('/irisservices/api/v1/public/protectionSources?environment=kPhysical');
  print 'Response: '.$client->responseContent()."\n" if exists $options{d};
  print 'Response status: '.$client->responseCode()."\n" if exists $options{d};
  my $physicalProtectedSources=decode_json $client->responseContent();  
  my $physicalProtectedCount=$physicalProtectedSources->[0]->{'protectedSourcesSummary'}->[0]->{'leavesCount'}; # Count sources for output
  print "Physical Count: $physicalProtectedCount\n" if exists $options{d};
  my $protectedCount=int($vmProtectedCount + $physicalProtectedCount);
  my $totalCount=int($totalCount + $physicalProtectedCount);
  my $currTime = int($seconds * 1000000 + $microseconds);
  my $pastTime = int ($currTime - 86399999999);
  print "Current Epoch Time: $currTime\n" if exists $options{d};
  print "Past Epoch Time: $pastTime\n" if exists $options{d};
  $client=REST::Client->new();
  $client->setHost("https://$options{c}");
  $client->addHeader("Accept", "application/json");
  $client->addHeader("Authorization", "$tokenType $accessToken");
  $client->GET('/irisservices/api/v1/public/protectionRuns?startTimeUsecs='.$pastTime.'&excludeErrorRuns=true&numRuns=300&excludeTasks=true');
  print 'Response: '.$client->responseContent()."\n" if exists $options{d};
  print 'Response status: '.$client->responseCode()."\n" if exists $options{d};
  my $successJobs=decode_json $client->responseContent();  
  my $successCount=$#{$successJobs} + 1; # Count sources for output
  # Bytes Calculations
  foreach my $f (@{$successJobs}){
    $totalSourceSizeBytes=$totalSourceSizeBytes+$f->{'backupRun'}{'stats'}{'totalSourceSizeBytes'};
    $totalBytesReadFromSource=$totalBytesReadFromSource+$f->{'backupRun'}{'stats'}{'totalBytesReadFromSource'};
    $totalLogicalBackupSizeBytes=$totalLogicalBackupSizeBytes+$f->{'backupRun'}{'stats'}{'totalLogicalBackupSizeBytes'};
    $totalPhysicalBackupSizeBytes=$totalPhysicalBackupSizeBytes+$f->{'backupRun'}{'stats'}{'totalPhysicalBackupSizeBytes'};
  }

  $client=REST::Client->new();
  $client->setHost("https://$options{c}");
  $client->addHeader("Accept", "application/json");
  $client->addHeader("Authorization", "$tokenType $accessToken");
  $client->GET('/irisservices/api/v1/public/protectionRuns?startTimeUsecs='.$pastTime.'&excludeErrorRuns=false&numRuns=300&excludeTasks=true');
  print 'Response: '.$client->responseContent()."\n" if exists $options{d};
  print 'Response status: '.$client->responseCode()."\n" if exists $options{d};
  my $allJobs=decode_json $client->responseContent();  
  my $allCount=$#{$allJobs} + 1; # Count sources for output
  my $failedCount=int ($allCount - $successCount);
  print "Protections Summary\n";
  print "===================\n";
  print "Protected Sources: $protectedCount of $totalCount\n\n"; 
 
  print "Job Summary (24 Hours)\n"; 
  print "======================\n";
  print "Successful Jobs: $successCount\n"; 
  print "Failed Jobs: $failedCount\n"; 
  print "Total Jobs: $allCount\n\n"; 
  
  print "Backup Stats (24 Hours)\n";
  print "=======================\n";
  printf "Total Source Data          : %.1f $sizeType\n",$totalSourceSizeBytes/$sizeValue;
  printf "Total Data Read From Source: %.1f $sizeType\n",$totalBytesReadFromSource/$sizeValue;
  printf "Total Logical Storage      : %.1f $sizeType\n",$totalLogicalBackupSizeBytes/$sizeValue;
  printf "Total Physical Storage     : %.1f $sizeType\n",$totalPhysicalBackupSizeBytes/$sizeValue;
   
}

sub getKbytesInfo{
  

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
    $testAccess->GET('/irisservices/api/v1/public/alerts?alertSeverityList[]=kCritical&alertCategoryList[]=kBackupRestore&alertStateList[]=kOpen');
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
getopts("hdc:u:p:s:j", \%options);

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
      print "Authentication cookie exists you can delete the cookie $authCookie to prompt for password\n";
      exit(4);
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
getSourceInfo();
