#!/usr/bin/perl -w

use ycp;
use Data::Dumper;

# stratum 2 first
my $mills_url1 = "http://www.eecis.udel.edu/~mills/ntp/clock2b.html";
my $mills_url2 = "http://www.eecis.udel.edu/~mills/ntp/clock1b.html";

my @mills_urls = ($mills_url1, $mills_url2);

my $server_ref = undef;
my @servers = ();

sub push_server_info {
    push @servers, $server_ref;
    $server_ref = undef;
}

my $stratum = 3;

# parse NTP servers from web page
foreach my $url (@mills_urls) {
    $stratum = $stratum - 1;
    open (PAGE, "wget -O - $url |");
    while ($line = <PAGE>)
    {
	if ($line =~ /<li>[ \t]*([a-zA-Z0-9]{2})[ \t:]+(([^. \t:]{2,})[ \t:]+)?([-.a-zA-Z0-9]+)[^-.a-zA-Z0-9]+/)
	{
	    if (defined ($server_ref))
	    {
		push_server_info ();
	    }
	    $server_ref = {
		"country" => $1,
		"address" => $4,
		"stratum" => $stratum,
	    };
	    if (defined ($2))
	    {
		$server_ref->{"state"} = $2;
	    }
	}
	elsif ($line =~ /Location: (.*)<br>/)
	{
	    $server_ref->{"location"} = $1;
	}
	elsif ($line =~ /Geographic Coordinates: (.*)<br>/)
	{
	    $server_ref->{"coordinates"} = $1;
	}
	elsif ($line =~ /Synchronization: (.*)<br>/)
	{
	    $server_ref->{"synchronization"} = $1
	}
	elsif ($line =~ /Service Area: (.*)<br>/)
	{
	    $server_ref->{"service_area"} = $1;
	}
	elsif ($line =~ /Access Policy: (.*)<br>/)
	{
	    $server_ref->{"access_policy"} = $1;
	}
	elsif ($line =~ /Contacts: (.*)<br>/)
	{
	    $server_ref->{"contacts"} = $1;
	}
    }
    close (PAGE);
    if (defined ($server_ref))
    {
	push_server_info ();
    }
}

#test all of them
@servers = grep {
    my $hostname = $_->{"address"};
    my $status = system ("sudo /usr/sbin/ntpdate $hostname");
    $status == 0;
} @servers;

open (OUT, ">servers.ycp");
print OUT "[\n";
foreach my $sr (@servers) {
    print OUT "  \$[\n";
    my %s = %{$sr};
    foreach my $key (sort (keys (%{$sr}))) {
	my $value = $sr->{$key};
	$value =~ s/\"/\\\"/g;
	print OUT "    \"$key\" : \"$value\",\n";
    }
    print OUT "  ],\n";
}
print OUT "]\n";
close (OUT);


#ycp::Return (\@servers, 1);

