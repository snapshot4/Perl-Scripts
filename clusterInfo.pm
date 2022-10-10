#!/usr/bin/perl

#Author: Brian Doyle
#Name: clusterList.pm
#Description: This is meant to be a secured file containing the cluster information.

package clusterInfo;

sub clusterList {
  my @clusters = (
    {
      'cluster'		=>	'10.99.1.175',
      'username'	=>	'bdoyle',
      'password'	=>	'madden*dialog6LOONY',
      'domain'		=>	'LOCAL',
      'databaseName'	=>	'postgres',
      'region'		=>	'NAM',
    },
  );
}

1;
